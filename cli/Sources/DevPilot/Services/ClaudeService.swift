import Foundation

struct ClaudeService {
    enum Error: Swift.Error {
        case nonZeroExit(Int32, stderr: String)
        case jsonParsingFailed(String)
    }

    func call<T: Decodable>(
        prompt: String,
        jsonSchema: String,
        workingDirectory: URL? = nil
    ) async throws -> T {
        fatalError("Not yet implemented")
    }
}
