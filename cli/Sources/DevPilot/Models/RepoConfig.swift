import Foundation

struct ReposConfig: Codable {
    let repositories: [Repository]

    enum LoadError: Error, LocalizedError {
        case fileNotFound(String)
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Config file not found: \(path)"
            case .decodingFailed(let detail):
                return "Failed to decode repos.json: \(detail)"
            }
        }
    }

    static func load(from path: String? = nil) throws -> ReposConfig {
        let configPath: String
        if let path {
            configPath = path
        } else {
            // Default: repos.json next to the executable's ancestor directory
            // In practice, the CLI lives at cli/.build/debug/dev-pilot,
            // so we look for repos.json in the project root (3 levels up).
            // Alternatively, check current working directory.
            let cwd = FileManager.default.currentDirectoryPath
            configPath = (cwd as NSString).appendingPathComponent("repos.json")
        }

        guard FileManager.default.fileExists(atPath: configPath) else {
            throw LoadError.fileNotFound(configPath)
        }

        let url = URL(fileURLWithPath: configPath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadError.fileNotFound(configPath)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ReposConfig.self, from: data)
        } catch {
            throw LoadError.decodingFailed(error.localizedDescription)
        }
    }

    func repository(withId id: String) -> Repository? {
        repositories.first { $0.id == id }
    }
}

struct Repository: Codable {
    let id: String
    let path: String
    let description: String
    let recentFocus: String?
    let skills: [String]
    let architectureDocs: [String]
    let verification: Verification
    let pullRequest: PullRequestConfig
}

struct Verification: Codable {
    let commands: [String]
    let notes: String?
}

struct PullRequestConfig: Codable {
    let baseBranch: String
    let branchNamingConvention: String
    let template: String?
    let notes: String?
}
