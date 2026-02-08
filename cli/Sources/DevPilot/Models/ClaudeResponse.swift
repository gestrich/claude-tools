import Foundation

struct RepoMatch: Codable {
    let repoId: String
    let interpretedRequest: String
}

struct GeneratedPlan: Codable {
    let planContent: String
    let filename: String
}

struct PhaseResult: Codable {
    let success: Bool
}
