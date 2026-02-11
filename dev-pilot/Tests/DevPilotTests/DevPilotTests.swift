import Testing
import Foundation
@testable import dev_pilot

// MARK: - ReposConfig Tests

@Suite("ReposConfig Loading")
struct ReposConfigTests {
    @Test func loadFromValidJSON() throws {
        let json = """
        {
          "repositories": [
            {
              "id": "test-repo",
              "path": "/tmp/test-repo",
              "description": "A test repository",
              "recentFocus": "Testing features",
              "skills": ["swift-testing"],
              "architectureDocs": ["docs/arch.md"],
              "verification": {
                "commands": ["swift test"],
                "notes": "Run all tests"
              },
              "pullRequest": {
                "baseBranch": "main",
                "branchNamingConvention": "feature/description",
                "template": null,
                "notes": null
              }
            }
          ]
        }
        """

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-repos-\(UUID().uuidString).json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = try ReposConfig.load(from: tmpFile.path)
        #expect(config.repositories.count == 1)

        let repo = config.repositories[0]
        #expect(repo.id == "test-repo")
        #expect(repo.path == "/tmp/test-repo")
        #expect(repo.description == "A test repository")
        #expect(repo.recentFocus == "Testing features")
        #expect(repo.skills == ["swift-testing"])
        #expect(repo.architectureDocs == ["docs/arch.md"])
        #expect(repo.verification.commands == ["swift test"])
        #expect(repo.verification.notes == "Run all tests")
        #expect(repo.pullRequest.baseBranch == "main")
        #expect(repo.pullRequest.branchNamingConvention == "feature/description")
        #expect(repo.pullRequest.template == nil)
        #expect(repo.pullRequest.notes == nil)
    }

    @Test func loadWithNullOptionalFields() throws {
        let json = """
        {
          "repositories": [
            {
              "id": "minimal",
              "path": "/tmp/minimal",
              "description": "Minimal config",
              "recentFocus": null,
              "skills": [],
              "architectureDocs": [],
              "verification": {
                "commands": [],
                "notes": null
              },
              "pullRequest": {
                "baseBranch": "main",
                "branchNamingConvention": "feature/desc",
                "template": null,
                "notes": null
              }
            }
          ]
        }
        """

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-repos-\(UUID().uuidString).json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = try ReposConfig.load(from: tmpFile.path)
        #expect(config.repositories[0].recentFocus == nil)
        #expect(config.repositories[0].skills.isEmpty)
        #expect(config.repositories[0].verification.notes == nil)
    }

    @Test func loadMultipleRepositories() throws {
        let json = """
        {
          "repositories": [
            {
              "id": "repo-a",
              "path": "/tmp/a",
              "description": "Repo A",
              "recentFocus": null,
              "skills": [],
              "architectureDocs": [],
              "verification": {"commands": [], "notes": null},
              "pullRequest": {"baseBranch": "main", "branchNamingConvention": "feat/x", "template": null, "notes": null}
            },
            {
              "id": "repo-b",
              "path": "/tmp/b",
              "description": "Repo B",
              "recentFocus": "Working on B",
              "skills": ["skill-1", "skill-2"],
              "architectureDocs": ["doc1.md", "doc2.md"],
              "verification": {"commands": ["make test", "make lint"], "notes": "CI required"},
              "pullRequest": {"baseBranch": "develop", "branchNamingConvention": "feature/JIRA-xxx", "template": "pr-template.md", "notes": "Add reviewers"}
            }
          ]
        }
        """

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-repos-\(UUID().uuidString).json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = try ReposConfig.load(from: tmpFile.path)
        #expect(config.repositories.count == 2)
        #expect(config.repositories[1].skills.count == 2)
        #expect(config.repositories[1].verification.commands.count == 2)
        #expect(config.repositories[1].pullRequest.template == "pr-template.md")
    }

    @Test func lookupRepositoryById() throws {
        let json = """
        {
          "repositories": [
            {
              "id": "alpha",
              "path": "/tmp/alpha",
              "description": "Alpha repo",
              "recentFocus": null,
              "skills": [],
              "architectureDocs": [],
              "verification": {"commands": [], "notes": null},
              "pullRequest": {"baseBranch": "main", "branchNamingConvention": "f/x", "template": null, "notes": null}
            },
            {
              "id": "beta",
              "path": "/tmp/beta",
              "description": "Beta repo",
              "recentFocus": null,
              "skills": [],
              "architectureDocs": [],
              "verification": {"commands": [], "notes": null},
              "pullRequest": {"baseBranch": "main", "branchNamingConvention": "f/x", "template": null, "notes": null}
            }
          ]
        }
        """

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-repos-\(UUID().uuidString).json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = try ReposConfig.load(from: tmpFile.path)
        #expect(config.repository(withId: "alpha")?.path == "/tmp/alpha")
        #expect(config.repository(withId: "beta")?.path == "/tmp/beta")
        #expect(config.repository(withId: "nonexistent") == nil)
    }

    @Test func loadNonexistentFileThrows() {
        #expect(throws: ReposConfig.LoadError.self) {
            try ReposConfig.load(from: "/nonexistent/path/repos.json")
        }
    }

    @Test func loadInvalidJSONThrows() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-repos-\(UUID().uuidString).json")
        try "not valid json".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        #expect(throws: ReposConfig.LoadError.self) {
            try ReposConfig.load(from: tmpFile.path)
        }
    }

    @Test func loadMissingRequiredFieldsThrows() throws {
        let json = """
        {"repositories": [{"id": "test"}]}
        """

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-repos-\(UUID().uuidString).json")
        try json.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        #expect(throws: ReposConfig.LoadError.self) {
            try ReposConfig.load(from: tmpFile.path)
        }
    }

    @Test func loadActualReposJSON() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DevPilotTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // cli/
        let reposPath = projectRoot.appendingPathComponent("repos.json").path

        guard FileManager.default.fileExists(atPath: reposPath) else {
            return
        }

        let config = try ReposConfig.load(from: reposPath)
        #expect(config.repositories.count >= 1)

        for repo in config.repositories {
            #expect(!repo.id.isEmpty)
            #expect(!repo.path.isEmpty)
            #expect(!repo.description.isEmpty)
        }
    }
}

// MARK: - Model Codable Tests

@Suite("Model Serialization")
struct ModelCodableTests {
    @Test func repoMatchRoundTrip() throws {
        let original = RepoMatch(repoId: "my-repo", interpretedRequest: "Fix the login bug")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RepoMatch.self, from: data)
        #expect(decoded.repoId == original.repoId)
        #expect(decoded.interpretedRequest == original.interpretedRequest)
    }

    @Test func generatedPlanRoundTrip() throws {
        let original = GeneratedPlan(
            planContent: "## Plan\n\n- [ ] Phase 1: Do things",
            filename: "fix-login-bug"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeneratedPlan.self, from: data)
        #expect(decoded.planContent == original.planContent)
        #expect(decoded.filename == original.filename)
    }

    @Test func phaseResultRoundTrip() throws {
        for value in [true, false] {
            let original = PhaseResult(success: value)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(PhaseResult.self, from: data)
            #expect(decoded.success == value)
        }
    }

    @Test func phaseStatusRoundTrip() throws {
        let original = PhaseStatus(description: "Implement feature", status: "completed")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhaseStatus.self, from: data)
        #expect(decoded.description == original.description)
        #expect(decoded.status == original.status)
        #expect(decoded.isCompleted)
    }

    @Test func phaseStatusIsCompleted() {
        let completed = PhaseStatus(description: "Done", status: "completed")
        let pending = PhaseStatus(description: "Todo", status: "pending")
        let inProgress = PhaseStatus(description: "Working", status: "in_progress")

        #expect(completed.isCompleted)
        #expect(!pending.isCompleted)
        #expect(!inProgress.isCompleted)
    }

    @Test func phaseStatusResponseRoundTrip() throws {
        let original = PhaseStatusResponse(
            phases: [
                PhaseStatus(description: "Phase 1", status: "completed"),
                PhaseStatus(description: "Phase 2", status: "pending"),
            ],
            nextPhaseIndex: 1
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhaseStatusResponse.self, from: data)
        #expect(decoded.phases.count == 2)
        #expect(decoded.nextPhaseIndex == 1)
        #expect(decoded.phases[0].isCompleted)
        #expect(!decoded.phases[1].isCompleted)
    }

    @Test func phaseStatusResponseAllComplete() throws {
        let response = PhaseStatusResponse(
            phases: [
                PhaseStatus(description: "Phase 1", status: "completed"),
            ],
            nextPhaseIndex: -1
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(PhaseStatusResponse.self, from: data)
        #expect(decoded.nextPhaseIndex == -1)
    }

    @Test func repoMatchDecodesFromClaude() throws {
        let json = """
        {"repoId": "example-ios", "interpretedRequest": "Fix waypoint disappearing after save"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RepoMatch.self, from: data)
        #expect(decoded.repoId == "example-ios")
        #expect(decoded.interpretedRequest == "Fix waypoint disappearing after save")
    }

    @Test func generatedPlanDecodesFromClaude() throws {
        let json = """
        {"planContent": "## Fix Waypoint Bug\\n\\n## - [ ] Phase 1: Interpret", "filename": "fix-waypoint-bug"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GeneratedPlan.self, from: data)
        #expect(decoded.filename == "fix-waypoint-bug")
        #expect(decoded.planContent.contains("Phase 1"))
    }
}

// MARK: - TimerDisplay Tests

@Suite("TimerDisplay")
struct TimerDisplayTests {
    @Test func formatTimeZero() {
        #expect(TimerDisplay.formatTime(0) == "00:00:00")
    }

    @Test func formatTimeSeconds() {
        #expect(TimerDisplay.formatTime(45) == "00:00:45")
    }

    @Test func formatTimeMinutes() {
        #expect(TimerDisplay.formatTime(90) == "00:01:30")
    }

    @Test func formatTimeHours() {
        #expect(TimerDisplay.formatTime(3661) == "01:01:01")
    }

    @Test func formatTimeLargeValue() {
        #expect(TimerDisplay.formatTime(5400) == "01:30:00")
    }

    @Test func formatTimeDefaultMaxRuntime() {
        #expect(TimerDisplay.formatTime(90 * 60) == "01:30:00")
    }
}

// MARK: - Repository Model Tests

@Suite("Repository Model")
struct RepositoryModelTests {
    @Test func verificationWithNotes() throws {
        let json = """
        {"commands": ["swift test", "swift build"], "notes": "Use iPhone 16 simulator"}
        """
        let decoded = try JSONDecoder().decode(Verification.self, from: json.data(using: .utf8)!)
        #expect(decoded.commands.count == 2)
        #expect(decoded.notes == "Use iPhone 16 simulator")
    }

    @Test func verificationWithoutNotes() throws {
        let json = """
        {"commands": ["swift test"], "notes": null}
        """
        let decoded = try JSONDecoder().decode(Verification.self, from: json.data(using: .utf8)!)
        #expect(decoded.commands == ["swift test"])
        #expect(decoded.notes == nil)
    }

    @Test func pullRequestConfigFull() throws {
        let json = """
        {
          "baseBranch": "develop",
          "branchNamingConvention": "feature/JIRA-123-desc",
          "template": "pr-template.md",
          "notes": "Assign reviewer"
        }
        """
        let decoded = try JSONDecoder().decode(PullRequestConfig.self, from: json.data(using: .utf8)!)
        #expect(decoded.baseBranch == "develop")
        #expect(decoded.branchNamingConvention == "feature/JIRA-123-desc")
        #expect(decoded.template == "pr-template.md")
        #expect(decoded.notes == "Assign reviewer")
    }

    @Test func pullRequestConfigMinimal() throws {
        let json = """
        {
          "baseBranch": "main",
          "branchNamingConvention": "feat/x",
          "template": null,
          "notes": null
        }
        """
        let decoded = try JSONDecoder().decode(PullRequestConfig.self, from: json.data(using: .utf8)!)
        #expect(decoded.template == nil)
        #expect(decoded.notes == nil)
    }
}

// MARK: - CLI Argument Parsing Tests

@Suite("CLI Argument Parsing")
struct CLIParsingTests {
    @Test func planCommandParsesText() throws {
        let cmd = try Plan.parse(["Fix the login bug"])
        #expect(cmd.text == "Fix the login bug")
        #expect(!cmd.execute)
        #expect(cmd.config == nil)
    }

    @Test func planCommandWithExecuteFlag() throws {
        let cmd = try Plan.parse(["--execute", "Fix the login bug"])
        #expect(cmd.text == "Fix the login bug")
        #expect(cmd.execute)
    }

    @Test func planCommandWithConfig() throws {
        let cmd = try Plan.parse(["--config", "/tmp/repos.json", "Fix the login bug"])
        #expect(cmd.config == "/tmp/repos.json")
        #expect(cmd.text == "Fix the login bug")
    }

    @Test func planCommandWithAllOptions() throws {
        let cmd = try Plan.parse(["--execute", "--config", "/tmp/repos.json", "Some task"])
        #expect(cmd.execute)
        #expect(cmd.config == "/tmp/repos.json")
        #expect(cmd.text == "Some task")
    }

    @Test func executeCommandDefaults() throws {
        let cmd = try Execute.parse([])
        #expect(cmd.plan == nil)
        #expect(cmd.maxMinutes == 90)
    }

    @Test func executeCommandWithPlan() throws {
        let cmd = try Execute.parse(["--plan", "/tmp/plan.md"])
        #expect(cmd.plan == "/tmp/plan.md")
    }

    @Test func executeCommandWithAllOptions() throws {
        let cmd = try Execute.parse([
            "--plan", "/tmp/plan.md",
            "--max-minutes", "120"
        ])
        #expect(cmd.plan == "/tmp/plan.md")
        #expect(cmd.maxMinutes == 120)
    }

    @Test func executeCommandInvalidMaxMinutesRejects() {
        #expect(throws: Swift.Error.self) {
            _ = try Execute.parse(["--max-minutes", "not-a-number"])
        }
    }
}

// MARK: - ClaudeService Error Tests

@Suite("ClaudeService Errors")
struct ClaudeServiceErrorTests {
    @Test func nonZeroExitDescription() {
        let error = ClaudeService.Error.nonZeroExit(1, stderr: "Something went wrong")
        #expect(error.errorDescription?.contains("code 1") == true)
        #expect(error.errorDescription?.contains("Something went wrong") == true)
    }

    @Test func jsonParsingFailedDescription() {
        let error = ClaudeService.Error.jsonParsingFailed("unexpected token")
        #expect(error.errorDescription?.contains("unexpected token") == true)
    }

    @Test func claudeErrorNoResultDescription() {
        let error = ClaudeService.Error.claudeError(result: nil, rawResultLine: nil)
        #expect(error.errorDescription?.contains("no result event received") == true)
    }
}

// MARK: - PlanGenerator Error Tests

@Suite("PlanGenerator Errors")
struct PlanGeneratorErrorTests {
    @Test func noMatchingRepoDescription() {
        let error = PlanGenerator.Error.noMatchingRepo("could not determine")
        #expect(error.errorDescription?.contains("No matching repository") == true)
    }

    @Test func repoNotFoundDescription() {
        let error = PlanGenerator.Error.repoNotFound("unknown-repo")
        #expect(error.errorDescription?.contains("unknown-repo") == true)
    }

    @Test func writeErrorDescription() {
        let error = PlanGenerator.Error.writeError("permission denied")
        #expect(error.errorDescription?.contains("permission denied") == true)
    }
}

// MARK: - PhaseExecutor Error Tests

@Suite("PhaseExecutor Errors")
struct PhaseExecutorErrorTests {
    @Test func planNotFoundDescription() {
        let error = PhaseExecutor.Error.planNotFound("/tmp/missing.md")
        #expect(error.errorDescription?.contains("/tmp/missing.md") == true)
    }

    @Test func phaseFailedDescription() {
        let error = PhaseExecutor.Error.phaseFailed(2, "Implement feature X")
        #expect(error.errorDescription?.contains("Phase 3") == true)
        #expect(error.errorDescription?.contains("Implement feature X") == true)
    }
}

// MARK: - ReposConfig LoadError Tests

@Suite("ReposConfig LoadError")
struct ReposConfigLoadErrorTests {
    @Test func fileNotFoundDescription() {
        let error = ReposConfig.LoadError.fileNotFound("/missing/path")
        #expect(error.errorDescription?.contains("/missing/path") == true)
    }

    @Test func decodingFailedDescription() {
        let error = ReposConfig.LoadError.decodingFailed("missing key 'id'")
        #expect(error.errorDescription?.contains("missing key 'id'") == true)
    }
}
