import ArgumentParser
import Foundation

struct Execute: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute phases from a planning document"
    )

    @Option(help: "Path to planning document")
    var plan: String?

    @Option(help: "Path to target repository (auto-detected from plan path if omitted)")
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

        let repos = try ReposConfig.load(from: config)
        let jobDir = planURL.deletingLastPathComponent()

        let mainRepoURL: URL
        if let repo {
            mainRepoURL = URL(fileURLWithPath: (repo as NSString).standardizingPath)
        } else if let repoId = JobDirectory.deriveRepoId(from: planURL),
                  let repoConfig = repos.repository(withId: repoId) {
            mainRepoURL = URL(fileURLWithPath: repoConfig.path)
        } else {
            throw ValidationError("Cannot determine repository. Use --repo or ensure plan is in ~/Desktop/dev-pilot/<repo-id>/<job-name>/plan.md")
        }

        let logService = try LogService(directory: jobDir, label: "execute")
        logService.log("dev-pilot execute started")
        logService.log("Plan: \(planURL.path)")
        logService.log("Repo: \(mainRepoURL.path)")

        guard let repoConfig = repos.repositories.first(where: { $0.path == mainRepoURL.path }) else {
            throw ValidationError("Repository at \(mainRepoURL.path) not found in repos.json")
        }

        let worktreeService = WorktreeService(logService: logService)
        let worktreeDestination = JobDirectory(url: jobDir).worktreeURL
        let worktreeURL = try worktreeService.createWorktree(
            repoPath: mainRepoURL,
            baseBranch: repoConfig.pullRequest.baseBranch,
            destination: worktreeDestination
        )

        let executor = PhaseExecutor(claudeService: ClaudeService(), logService: logService)
        do {
            try await executor.execute(
                planPath: planURL,
                repoPath: worktreeURL,
                maxMinutes: maxMinutes,
                repository: repoConfig,
                worktreeService: worktreeService
            )
        } catch {
            logService.log("\nCleaning up worktree due to error...")
            try? worktreeService.removeWorktree(worktreePath: worktreeURL)
            throw error
        }

        logService.log("Log file: \(logService.logFileURL.path)")
    }
}
