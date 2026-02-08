import ArgumentParser

struct Execute: ParsableCommand {
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

    func run() throws {
        print("Executing plan...")
    }
}
