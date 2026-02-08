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

        guard let repo else {
            throw ValidationError("--repo is required for execution")
        }

        let mainRepoURL = URL(fileURLWithPath: (repo as NSString).standardizingPath)

        // Load repo config to get base branch
        let repos = try ReposConfig.load(from: config)

        // Try to find the matching repo config by path
        guard let repoConfig = repos.repositories.first(where: { $0.path == mainRepoURL.path }) else {
            throw ValidationError("Repository at \(mainRepoURL.path) not found in repos.json")
        }

        // Create worktree
        let worktreeService = WorktreeService()
        let worktreeURL = try worktreeService.createWorktree(
            repoPath: mainRepoURL,
            baseBranch: repoConfig.pullRequest.baseBranch
        )

        // Execute in worktree
        let executor = PhaseExecutor(claudeService: ClaudeService())
        do {
            try await executor.execute(
                planPath: planURL,
                repoPath: worktreeURL,
                maxMinutes: maxMinutes,
                worktreeService: worktreeService
            )
        } catch {
            // Clean up worktree on error
            print("\nCleaning up worktree due to error...")
            try? worktreeService.removeWorktree(worktreePath: worktreeURL)
            throw error
        }
    }
}
