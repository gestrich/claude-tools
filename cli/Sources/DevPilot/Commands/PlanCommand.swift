import ArgumentParser

struct Plan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate an implementation plan from voice text"
    )

    @Argument(help: "Voice-transcribed text describing the task")
    var text: String

    @Flag(help: "Execute the plan immediately after generating it")
    var execute = false

    @Option(help: "Path to repos.json config")
    var config: String?

    func run() throws {
        print("Planning: \(text)")
    }
}
