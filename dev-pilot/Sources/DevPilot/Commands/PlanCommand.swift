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
        let label = "plan-" + String(
            text.prefix(40)
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        )
        let logService = try LogService(label: label)

        let repos = try ReposConfig.load(from: config)
        logService.log("Loaded \(repos.repositories.count) repositories from config")
        logService.log("Voice text: \(text)")

        let generator = PlanGenerator(claudeService: ClaudeService(), logService: logService)
        let (planURL, matchedRepo) = try await generator.generate(voiceText: text, repos: repos)

        logService.log("Log file: \(logService.logFileURL.path)")

        if execute {
            logService.log("\nStarting execution...")
            var args = ["--plan", planURL.path, "--repo", matchedRepo.path]
            if let config = config {
                args += ["--config", config]
            }
            let executeCmd = try Execute.parse(args)
            try await executeCmd.run()
        }
    }
}
