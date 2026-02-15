import ArgumentParser
import Foundation

struct Execute: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute phases from a planning document"
    )

    @Option(help: "Path to planning document")
    var plan: String?

    @Option(help: "Maximum runtime in minutes")
    var maxMinutes: Int = 90

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

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let logDir = JobDirectory.baseURL.appendingPathComponent("logs")
        let planName = planURL.deletingPathExtension().lastPathComponent
        let logService = try LogService(directory: logDir, label: "execute-\(planName)")
        logService.log("dev-pilot execute started")
        logService.log("Plan: \(planURL.path)")
        logService.log("Repo: \(cwd.path)")

        let executor = PhaseExecutor(claudeService: ClaudeService(), logService: logService)
        try await executor.execute(
            planPath: planURL,
            repoPath: cwd,
            maxMinutes: maxMinutes
        )

        logService.log("Log file: \(logService.logFileURL.path)")
    }
}
