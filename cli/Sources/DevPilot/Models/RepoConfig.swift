import Foundation

struct ReposConfig: Codable {
    let repositories: [Repository]
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
