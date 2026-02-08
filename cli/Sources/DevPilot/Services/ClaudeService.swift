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
        workingDirectory: URL? = nil
    ) async throws -> T {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "caffeinate", "-dimsu",
            "claude", "--dangerously-skip-permissions", "-p", "--verbose",
            "--output-format", "json",
            "--json-schema", jsonSchema,
            prompt
        ]

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw Error.nonZeroExit(process.terminationStatus, stderr: stderrString)
        }

        // With --verbose, output is a JSON array. The structured_output is in the last element.
        let jsonArray: [[String: Any]]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: stdoutData) as? [[String: Any]] else {
                throw Error.jsonParsingFailed("Expected JSON array at top level")
            }
            jsonArray = parsed
        } catch let error as Error {
            throw error
        } catch {
            throw Error.jsonParsingFailed(error.localizedDescription)
        }

        guard let lastElement = jsonArray.last,
              let structuredOutput = lastElement["structured_output"] else {
            throw Error.noStructuredOutput
        }

        let outputData = try JSONSerialization.data(withJSONObject: structuredOutput)
        do {
            return try JSONDecoder().decode(T.self, from: outputData)
        } catch {
            let rawJSON = String(data: outputData, encoding: .utf8) ?? "<unreadable>"
            throw Error.jsonParsingFailed("Could not decode \(T.self) from: \(rawJSON)")
        }
    }
}
