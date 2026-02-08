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
        print("Loaded \(repos.repositories.count) repositories from config")

        let generator = PlanGenerator(claudeService: ClaudeService())
        let (planURL, matchedRepo) = try await generator.generate(voiceText: text, repos: repos)

        if execute {
            print("\nStarting execution...")
            var args = ["--plan", planURL.path, "--repo", matchedRepo.path]
            if let config = config {
                args += ["--config", config]
            }
            let executeCmd = try Execute.parse(args)
            try await executeCmd.run()
        }
    }
}
