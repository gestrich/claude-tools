import Foundation

struct ClaudeService {
    enum Error: Swift.Error, LocalizedError {
        case nonZeroExit(Int32, stderr: String)
        case jsonParsingFailed(String)
        case noStructuredOutput

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let code, let stderr):
                return "Claude exited with code \(code): \(stderr)"
            case .jsonParsingFailed(let detail):
                return "Failed to parse Claude JSON output: \(detail)"
            case .noStructuredOutput:
                return "Claude response contained no structured_output"
            }
        }
    }

    func call<T: Decodable>(
        prompt: String,
        jsonSchema: String,
        workingDirectory: URL? = nil,
        logService: LogService? = nil,
        needsTools: Bool = true
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
        let streamParser = StreamParser()

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
                logService.writeRaw(data)
            } else {
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

        guard let structuredOutput = streamParser.structuredOutput else {
            throw Error.noStructuredOutput
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

/// Parses stream-json events from Claude CLI stdout.
/// Each line is a JSON object with a "type" field.
/// Streams assistant text content to the log/console.
/// Captures structured_output from the final "result" event.
private final class StreamParser: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var _structuredOutput: Any?

    var structuredOutput: Any? {
        lock.lock()
        defer { lock.unlock() }
        return _structuredOutput
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
            // Extract text content from assistant messages and stream it
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let blockType = block["type"] as? String {
                        if blockType == "text", let text = block["text"] as? String {
                            if let logService {
                                logService.writeRaw(Data((text).utf8))
                            } else {
                                Swift.print(text, terminator: "")
                            }
                        } else if blockType == "tool_use", let name = block["name"] as? String {
                            // Show tool use activity (but not StructuredOutput since that's internal)
                            if name != "StructuredOutput" {
                                let msg = "[tool: \(name)]\n"
                                if let logService {
                                    logService.writeRaw(Data(msg.utf8))
                                } else {
                                    Swift.print(msg, terminator: "")
                                }
                            }
                        }
                    }
                }
            }

        case "result":
            // Capture structured_output from the final result event
            if let so = json["structured_output"] {
                lock.lock()
                _structuredOutput = so
                lock.unlock()
            }

        default:
            break
        }
    }
}
