import Foundation

struct ClaudeService {
    enum Error: Swift.Error, LocalizedError {
        case nonZeroExit(Int32, stderr: String)
        case jsonParsingFailed(String)
        case claudeError(result: StreamResult?, rawResultLine: String?)

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let code, let stderr):
                return "Claude exited with code \(code): \(stderr)"
            case .jsonParsingFailed(let detail):
                return "Failed to parse Claude JSON output: \(detail)"
            case .claudeError(let result, let rawResultLine):
                guard let result else {
                    if let rawResultLine {
                        return "Claude failed: could not decode result event\n  Raw: \(rawResultLine)"
                    }
                    return "Claude failed: no result event received"
                }
                let turns = result.numTurns ?? 0
                let cost = result.totalCostUsd ?? 0
                let durationSec = (result.durationMs ?? 0) / 1000
                let reason: String
                switch result.subtype {
                case "error_max_turns":
                    reason = "Hit turn limit (\(turns) turns)"
                case "error_during_execution":
                    reason = "Error during execution"
                case "error_max_budget_usd":
                    reason = "Budget exceeded ($\(String(format: "%.2f", cost)))"
                case "error_max_structured_output_retries":
                    reason = "Failed to produce valid structured output after retries"
                case "success":
                    reason = "No structured_output in successful result"
                default:
                    reason = result.subtype ?? "unknown"
                }
                var msg = "Claude failed: \(reason)"
                msg += " | \(turns) turns, $\(String(format: "%.2f", cost)), \(durationSec)s"
                if let errors = result.errors, !errors.isEmpty {
                    msg += "\n  Errors: \(errors.joined(separator: "; "))"
                }
                return msg
            }
        }
    }

    func call<T: Decodable>(
        prompt: String,
        jsonSchema: String,
        workingDirectory: URL? = nil,
        logService: LogService? = nil,
        needsTools: Bool = true,
        silent: Bool = false,
        onStatusUpdate: ((String) -> Void)? = nil
    ) async throws -> T {
        let claudePath = findClaudePath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = [
            "caffeinate", "-dimsu",
            claudePath, "--dangerously-skip-permissions", "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--json-schema", jsonSchema
        ]
        args.append(prompt)
        process.arguments = args

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        var environment = ProcessInfo.processInfo.environment
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Users/bill/.local/bin"
        ]
        if let existingPath = environment["PATH"] {
            environment["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath
        } else {
            environment["PATH"] = additionalPaths.joined(separator: ":") + ":/usr/bin:/bin"
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Stream stdout line-by-line (stream-json emits one JSON event per line)
        let streamParser = StreamParser(silent: silent, onStatusUpdate: onStatusUpdate)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            streamParser.feed(data, logService: logService)
        }

        // Stream stderr to console/log
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let logService {
                if silent {
                    logService.writeToFile(data)
                } else {
                    logService.writeRaw(data)
                }
            } else if !silent {
                FileHandle.standardError.write(data)
            }
        }

        try process.run()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Drain any remaining stdout
        let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            streamParser.feed(remaining, logService: logService)
        }

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            throw Error.nonZeroExit(process.terminationStatus, stderr: stderrString)
        }

        let result = streamParser.streamResult
        let rawLine = streamParser.rawResultLine
        if result?.isError == true {
            throw Error.claudeError(result: result, rawResultLine: rawLine)
        }

        guard let structuredOutput = streamParser.structuredOutput else {
            throw Error.claudeError(result: result, rawResultLine: rawLine)
        }

        let outputData = try JSONSerialization.data(withJSONObject: structuredOutput)
        do {
            return try JSONDecoder().decode(T.self, from: outputData)
        } catch {
            let rawJSON = String(data: outputData, encoding: .utf8) ?? "<unreadable>"
            throw Error.jsonParsingFailed("Could not decode \(T.self) from: \(rawJSON). Error: \(error.localizedDescription)")
        }
    }

    private func findClaudePath() -> String {
        let possiblePaths = [
            "/Users/bill/.local/bin/claude",
            "/usr/local/bin/claude",
            (NSString(string: "~/.local/bin/claude").expandingTildeInPath),
            "claude"
        ]

        let fm = FileManager.default
        for path in possiblePaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            if fm.fileExists(atPath: expandedPath) || path == "claude" {
                return path
            }
        }

        return "claude"
    }
}

struct StreamResult: Decodable {
    let subtype: String?
    let isError: Bool
    let errors: [String]?
    let numTurns: Int?
    let totalCostUsd: Double?
    let durationMs: Int?
    let sessionId: String?
    let result: String?

    enum CodingKeys: String, CodingKey {
        case subtype
        case isError = "is_error"
        case errors
        case numTurns = "num_turns"
        case totalCostUsd = "total_cost_usd"
        case durationMs = "duration_ms"
        case sessionId = "session_id"
        case result
    }
}

private final class StreamParser: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var _structuredOutput: Any?
    private var _streamResult: StreamResult?
    private var _rawResultLine: String?
    private let silent: Bool
    private let onStatusUpdate: ((String) -> Void)?

    init(silent: Bool = false, onStatusUpdate: ((String) -> Void)? = nil) {
        self.silent = silent
        self.onStatusUpdate = onStatusUpdate
    }

    var structuredOutput: Any? {
        lock.lock()
        defer { lock.unlock() }
        return _structuredOutput
    }

    var streamResult: StreamResult? {
        lock.lock()
        defer { lock.unlock() }
        return _streamResult
    }

    var rawResultLine: String? {
        lock.lock()
        defer { lock.unlock() }
        return _rawResultLine
    }

    func feed(_ data: Data, logService: LogService?) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }

        lock.lock()
        buffer += chunk
        lock.unlock()

        // Process complete lines
        while let range = buffer.range(of: "\n") {
            lock.lock()
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            lock.unlock()

            guard !line.isEmpty else { continue }
            processLine(line, logService: logService)
        }
    }

    private func processLine(_ line: String, logService: LogService?) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "assistant":
            handleAssistantMessage(json, logService: logService)

        case "result":
            lock.lock()
            _rawResultLine = line
            _streamResult = try? JSONDecoder().decode(StreamResult.self, from: data)
            if let so = json["structured_output"] {
                _structuredOutput = so
            }
            lock.unlock()

        default:
            break
        }
    }

    private func handleAssistantMessage(_ json: [String: Any], logService: LogService?) {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return }

        for block in content {
            handleContentBlock(block, logService: logService)
        }
    }

    private func handleContentBlock(_ block: [String: Any], logService: LogService?) {
        guard let blockType = block["type"] as? String else { return }

        switch blockType {
        case "text":
            guard let text = block["text"] as? String else { return }
            emit(text, logService: logService)
            if let onStatusUpdate {
                let lastLine = text.split(separator: "\n", omittingEmptySubsequences: true).last.map(String.init)
                if let lastLine, !lastLine.isEmpty {
                    onStatusUpdate(lastLine)
                }
            }

        case "tool_use":
            guard let name = block["name"] as? String, name != "StructuredOutput" else { return }
            emit("[tool: \(name)]\n", logService: logService)
            onStatusUpdate?("[tool: \(name)]")

        default:
            break
        }
    }

    private func emit(_ text: String, logService: LogService?) {
        guard !silent else { return }
        if let logService {
            logService.writeRaw(Data(text.utf8))
        } else {
            Swift.print(text, terminator: "")
        }
    }
}
