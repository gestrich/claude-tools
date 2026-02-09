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

        let planFilename = planURL.deletingPathExtension().lastPathComponent
        let logService = try LogService(label: "execute-\(planFilename)")
        logService.log("dev-pilot execute started")
        logService.log("Plan: \(planURL.path)")
        logService.log("Repo: \(mainRepoURL.path)")

        let repos = try ReposConfig.load(from: config)

        guard let repoConfig = repos.repositories.first(where: { $0.path == mainRepoURL.path }) else {
            throw ValidationError("Repository at \(mainRepoURL.path) not found in repos.json")
        }

        let worktreeService = WorktreeService(logService: logService)
        let worktreeURL = try worktreeService.createWorktree(
            repoPath: mainRepoURL,
            baseBranch: repoConfig.pullRequest.baseBranch
        )

        // Copy plan file into the worktree so Claude reads/writes from one location
        let worktreePlanURL: URL
        let relativePlanPath = planURL.path.replacingOccurrences(of: mainRepoURL.path + "/", with: "")
        if relativePlanPath != planURL.path {
            let destURL = worktreeURL.appendingPathComponent(relativePlanPath)
            let fm = FileManager.default
            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: planURL, to: destURL)
            worktreePlanURL = destURL
            logService.log("Copied plan to worktree: \(destURL.path)")
        } else {
            worktreePlanURL = planURL
        }

        let executor = PhaseExecutor(claudeService: ClaudeService(), logService: logService)
        do {
            try await executor.execute(
                planPath: worktreePlanURL,
                repoPath: worktreeURL,
                maxMinutes: maxMinutes,
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
