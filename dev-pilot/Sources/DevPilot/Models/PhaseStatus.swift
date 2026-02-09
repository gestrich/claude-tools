import Foundation

struct PhaseStatus: Codable {
    let description: String
    let status: String

    var isCompleted: Bool {
        status == "completed"
    }
}

struct PhaseStatusResponse: Codable {
    let phases: [PhaseStatus]
    let nextPhaseIndex: Int
}
