import ArgumentParser

@main
struct DevPilot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev-pilot",
        abstract: "Voice-driven development pipeline",
        subcommands: [Plan.self, Execute.self]
    )
}
