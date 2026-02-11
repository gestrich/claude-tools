import ArgumentParser
import Foundation

struct Plan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate an implementation plan from voice text"
    )

    @Argument(help: "Voice-transcribed text describing the task")
    var text: String

    @Flag(help: "Execute the plan immediately after generating it")
    var execute = false

    @Option(help: "Path to repos.json config")
    var config: String?

    func run() async throws {
        let repos = try ReposConfig.load(from: config)

        let generator = PlanGenerator(claudeService: ClaudeService())
        let (jobDir, matchedRepo) = try await generator.generate(voiceText: text, repos: repos)

        let logService = try LogService(directory: jobDir.url, label: "plan")
        logService.log("Voice text: \(text)")
        logService.log("Matched repo: \(matchedRepo.id)")
        logService.log("Plan: \(jobDir.planURL.path)")
        logService.log("Log file: \(logService.logFileURL.path)")

        if execute {
            logService.log("\nStarting execution...")
            var args = ["--plan", jobDir.planURL.path]
            if let config = config {
                args += ["--config", config]
            }
            let executeCmd = try Execute.parse(args)
            try await executeCmd.run()
        }
    }
}
