import ArgumentParser
import Foundation

struct Execute: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute phases from a planning document"
    )

    @Option(help: "Path to planning document")
    var plan: String?

    @Option(help: "Path to target repository (sets working directory)")
    var repo: String?

    @Option(help: "Maximum runtime in minutes")
    var maxMinutes: Int = 90

    @Option(help: "Path to repos.json config")
    var config: String?

    func run() async throws {
        let planURL: URL

        if let plan {
            planURL = URL(fileURLWithPath: (plan as NSString).standardizingPath)
        } else {
            guard let selected = PhaseExecutor.selectPlanningDoc() else {
                throw ExitCode.failure
            }
            planURL = selected
        }

        let repoURL: URL?
        if let repo {
            repoURL = URL(fileURLWithPath: (repo as NSString).standardizingPath)
        } else {
            repoURL = nil
        }

        let executor = PhaseExecutor(claudeService: ClaudeService())
        try await executor.execute(planPath: planURL, repoPath: repoURL, maxMinutes: maxMinutes)
    }
}
