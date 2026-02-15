import Foundation

struct PhaseExecutor {
    let claudeService: ClaudeService
    let logService: LogService?

    init(claudeService: ClaudeService, logService: LogService? = nil) {
        self.claudeService = claudeService
        self.logService = logService
    }

    enum Error: Swift.Error, LocalizedError {
        case planNotFound(String)
        case phaseFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .planNotFound(let path):
                return "Planning document not found: \(path)"
            case .phaseFailed(let index, let description):
                return "Phase \(index + 1) failed: \(description)"
            }
        }
    }

    func execute(planPath: URL, repoPath: URL?, maxMinutes: Int, repository: Repository? = nil, worktreeService: WorktreeService? = nil) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: planPath.path) else {
            throw Error.planNotFound(planPath.path)
        }

        let maxRuntimeSeconds = maxMinutes * 60
        let scriptStart = Date()

        printHeader(planPath: planPath, maxRuntimeSeconds: maxRuntimeSeconds)

        if let githubUser = repository?.githubUser, let repoPath {
            switchGitHubUser(githubUser, repoPath: repoPath)
        }

        logColored("Fetching phase information...", color: .cyan)
        var statusResponse: PhaseStatusResponse = try await getPhaseStatus(planPath: planPath, repoPath: repoPath)
        var phases = statusResponse.phases
        var nextIndex = statusResponse.nextPhaseIndex

        printPhaseOverview(phases: phases)

        if nextIndex == -1 {
            logColored("All steps already complete!", color: .green)
            moveToCompleted(planPath: planPath, repoPath: repoPath)
            return
        }

        logColored("Starting from Step \(nextIndex + 1): \(phases[nextIndex].description)\n", color: .cyan)

        let timer = TimerDisplay(maxRuntimeSeconds: maxRuntimeSeconds, scriptStartTime: scriptStart)
        var phasesExecuted = 0

        while nextIndex != -1 {
            let elapsed = Date().timeIntervalSince(scriptStart)
            if Int(elapsed) >= maxRuntimeSeconds {
                logColored("Time limit reached (\(TimerDisplay.formatTime(maxRuntimeSeconds)))", color: .yellow)
                break
            }

            let phase = phases[nextIndex]
            let totalSteps = phases.count

            printSeparator()
            logColored("Step \(nextIndex + 1) of \(totalSteps) -> \(phase.description)", color: .yellow)
            printDivider()
            logColored("Running claude...\n", color: .blue)

            let phaseStart = Date()
            timer.start()

            let phaseResult: PhaseResult
            do {
                phaseResult = try await executePhase(
                    planPath: planPath,
                    phaseIndex: nextIndex,
                    description: phase.description,
                    repoPath: repoPath,
                    repository: repository,
                    onStatusUpdate: { timer.setStatusLine($0) }
                )
            } catch {
                timer.stop()
                let phaseElapsed = Int(Date().timeIntervalSince(phaseStart))
                let totalElapsed = Int(Date().timeIntervalSince(scriptStart))
                logColored("\nPhase \(nextIndex + 1) failed: \(error.localizedDescription)", color: .red)
                logColored("\u{23F1}  Phase time: \(TimerDisplay.formatTime(phaseElapsed)) | Total: \(TimerDisplay.formatTime(totalElapsed))", color: .cyan)
                throw Error.phaseFailed(nextIndex, phase.description)
            }

            timer.stop()

            let phaseElapsed = Int(Date().timeIntervalSince(phaseStart))
            let totalElapsed = Int(Date().timeIntervalSince(scriptStart))

            if !phaseResult.success {
                logColored("\nStep \(nextIndex + 1) reported failure", color: .red)
                logColored("\u{23F1}  Step time: \(TimerDisplay.formatTime(phaseElapsed)) | Total: \(TimerDisplay.formatTime(totalElapsed))", color: .cyan)
                throw Error.phaseFailed(nextIndex, phase.description)
            }

            logColored("\nStep \(nextIndex + 1) completed successfully", color: .green)
            logColored("\u{23F1}  Step time: \(TimerDisplay.formatTime(phaseElapsed)) | Total: \(TimerDisplay.formatTime(totalElapsed))", color: .cyan)
            printDivider()
            log("")

            phasesExecuted += 1

            logColored("Fetching updated phase status...", color: .cyan)
            timer.start()
            statusResponse = try await getPhaseStatus(planPath: planPath, repoPath: repoPath, onStatusUpdate: { timer.setStatusLine($0) })
            timer.stop()
            phases = statusResponse.phases
            nextIndex = statusResponse.nextPhaseIndex

            if nextIndex != -1 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        let totalTime = Int(Date().timeIntervalSince(scriptStart))
        printSeparator()

        if nextIndex == -1 {
            logColored("\u{2713} All steps completed successfully!", color: .green)
        } else {
            let remaining = phases.filter { !$0.isCompleted }.count
            logColored("Time limit reached — \(remaining) steps may remain", color: .yellow)
        }

        printSeparator()
        logColored("Total steps executed: \(phasesExecuted)", color: .green)
        logColored("Total time: \(TimerDisplay.formatTime(totalTime))", color: .cyan)
        logColored("Planning document: \(planPath.path)", color: .green)
        log("")

        if nextIndex == -1 {
            playCompletionSound()
            moveToCompleted(planPath: planPath, repoPath: repoPath)

            if let worktreeService = worktreeService, let repoPath = repoPath {
                log("")
                logColored("Cleaning up worktree...", color: .cyan)
                try? worktreeService.removeWorktree(worktreePath: repoPath)
            }
        }
    }

    // MARK: - Claude Calls

    private static let statusSchema = """
    {"type":"object","properties":{"phases":{"type":"array","items":{"type":"object","properties":{"description":{"type":"string"},"status":{"type":"string","enum":["pending","in_progress","completed"]}},"required":["description","status"]}},"nextPhaseIndex":{"type":"integer","description":"Index of the next phase to execute (0-based), or -1 if all complete"}},"required":["phases","nextPhaseIndex"]}
    """

    private static let executionSchema = """
    {"type":"object","properties":{"success":{"type":"boolean","description":"Whether the phase was completed successfully"}},"required":["success"]}
    """

    private func getPhaseStatus(planPath: URL, repoPath: URL?, onStatusUpdate: ((String) -> Void)? = nil) async throws -> PhaseStatusResponse {
        let prompt = """
        Look at \(planPath.path) and analyze the phased implementation plan.

        Return a JSON with:
        1. phases: Array of all phases with their description and current status (pending/in_progress/completed)
        2. nextPhaseIndex: The index (0-based) of the next phase to execute, or -1 if all phases are complete

        Determine status by checking if each phase has been marked as complete in the document.
        """

        return try await claudeService.call(
            prompt: prompt,
            jsonSchema: Self.statusSchema,
            workingDirectory: repoPath,
            logService: logService,
            silent: true,
            onStatusUpdate: onStatusUpdate
        )
    }

    private func executePhase(
        planPath: URL,
        phaseIndex: Int,
        description: String,
        repoPath: URL?,
        repository: Repository?,
        onStatusUpdate: ((String) -> Void)? = nil
    ) async throws -> PhaseResult {
        var ghInstructions = "\nWhen creating pull requests, ALWAYS use `gh pr create --draft`."
        if let githubUser = repository?.githubUser {
            ghInstructions += "\nBefore running any `gh` commands, first run `gh auth switch -u \(githubUser)`."
        }

        let prompt = """
        Look at \(planPath.path) for background.

        You are working on Phase \(phaseIndex + 1): \(description)

        Complete ONLY this phase by:
        1. Implementing the required changes
        2. Ensuring the build succeeds
        3. Updating the markdown document to mark this phase as completed with any relevant technical notes
        4. Committing your changes
        \(ghInstructions)

        Return success: true if the phase was completed successfully, false otherwise.
        """

        return try await claudeService.call(
            prompt: prompt,
            jsonSchema: Self.executionSchema,
            workingDirectory: repoPath,
            logService: logService,
            silent: true,
            onStatusUpdate: onStatusUpdate
        )
    }

    // MARK: - Interactive Plan Selection

    static func selectPlanningDoc(proposedDir: String = "docs/proposed") -> URL? {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(proposedDir)

        guard fm.fileExists(atPath: dir.path) else {
            Self.printColoredStatic("Error: Directory not found: \(proposedDir)", color: .red)
            return nil
        }

        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "md" }
                .sorted { a, b in
                    let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return aDate > bDate
                }
        } catch {
            Self.printColoredStatic("Error reading \(proposedDir): \(error.localizedDescription)", color: .red)
            return nil
        }

        let sorted = Array(files.prefix(5))

        guard !sorted.isEmpty else {
            Self.printColoredStatic("No .md files found in \(proposedDir)", color: .red)
            return nil
        }

        Self.printColoredStatic("No planning document specified.", color: .blue)
        print("Last \(ANSIColor.green.rawValue)\(sorted.count)\(ANSIColor.reset.rawValue) modified files in \(ANSIColor.green.rawValue)\(proposedDir)\(ANSIColor.reset.rawValue):\n")

        for (i, file) in sorted.enumerated() {
            print("  \(ANSIColor.yellow.rawValue)\(i + 1)\(ANSIColor.reset.rawValue)) \(file.lastPathComponent)")
        }

        print()
        Swift.print("Select a file to implement [1-\(sorted.count)] (default: 1): ", terminator: "")

        let input = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
        let selection = input.isEmpty ? "1" : input

        guard let idx = Int(selection), idx >= 1, idx <= sorted.count else {
            Self.printColoredStatic("Invalid selection.", color: .red)
            return nil
        }

        return sorted[idx - 1]
    }

    // MARK: - Completion Handling

    private func moveToCompleted(planPath: URL, repoPath: URL?) {
        let fm = FileManager.default
        let proposedDir = planPath.deletingLastPathComponent()
        let completedDir = proposedDir.deletingLastPathComponent().appendingPathComponent("completed")

        do {
            if !fm.fileExists(atPath: completedDir.path) {
                try fm.createDirectory(at: completedDir, withIntermediateDirectories: true)
            }
            let dest = completedDir.appendingPathComponent(planPath.lastPathComponent)
            try fm.moveItem(at: planPath, to: dest)
            logColored("Moved spec to \(dest.path)", color: .green)

            let gitDir = repoPath ?? proposedDir
            let gitAdd = Process()
            gitAdd.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            gitAdd.arguments = ["git", "add", planPath.path, dest.path]
            gitAdd.currentDirectoryURL = gitDir
            gitAdd.standardOutput = FileHandle.nullDevice
            gitAdd.standardError = FileHandle.nullDevice
            try gitAdd.run()
            gitAdd.waitUntilExit()

            let gitCommit = Process()
            gitCommit.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            gitCommit.arguments = ["git", "commit", "-m", "Move completed spec to docs/completed"]
            gitCommit.currentDirectoryURL = gitDir
            gitCommit.standardOutput = FileHandle.nullDevice
            gitCommit.standardError = FileHandle.nullDevice
            try gitCommit.run()
            gitCommit.waitUntilExit()

            logColored("Committed spec move", color: .green)
        } catch {
            logColored("Could not move spec: \(error.localizedDescription)", color: .yellow)
        }
    }

    private func openPullRequest(repoPath: URL, githubUser: String?) {
        if let githubUser {
            switchGitHubUser(githubUser, repoPath: repoPath)
        }

        let gh = Process()
        gh.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        gh.arguments = ["gh", "pr", "view", "--json", "url", "-q", ".url"]
        gh.currentDirectoryURL = repoPath
        let pipe = Pipe()
        gh.standardOutput = pipe
        gh.standardError = FileHandle.nullDevice

        do {
            try gh.run()
            gh.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let urlString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlString.isEmpty else {
                logColored("No pull request found to open", color: .yellow)
                return
            }

            logColored("Opening PR: \(urlString)", color: .green)
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = [urlString]
            try open.run()
            open.waitUntilExit()
        } catch {
            logColored("Could not open PR: \(error.localizedDescription)", color: .yellow)
        }
    }

    private func switchGitHubUser(_ user: String, repoPath: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "switch", "-u", user]
        process.currentDirectoryURL = repoPath
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                logColored("Switched to GitHub user: \(user)", color: .cyan)
            } else {
                logColored("Warning: Could not switch to GitHub user '\(user)'", color: .yellow)
            }
        } catch {
            logColored("Warning: Could not switch to GitHub user '\(user)': \(error.localizedDescription)", color: .yellow)
        }
    }

    private func playCompletionSound() {
        for _ in 0..<2 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = ["/System/Library/Sounds/Glass.aiff"]
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: - Terminal Output

    private enum ANSIColor: String {
        case red = "\u{1B}[0;31m"
        case green = "\u{1B}[0;32m"
        case yellow = "\u{1B}[1;33m"
        case blue = "\u{1B}[0;34m"
        case cyan = "\u{1B}[0;36m"
        case reset = "\u{1B}[0m"
    }

    private static func printColoredStatic(_ text: String, color: ANSIColor) {
        print("\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)")
    }

    private func log(_ message: String) {
        if let logService {
            logService.log(message)
        } else {
            print(message)
        }
    }

    private func logColored(_ text: String, color: ANSIColor) {
        let formatted = "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
        if let logService {
            logService.log(formatted)
        } else {
            print(formatted)
        }
    }

    private func printHeader(planPath: URL, maxRuntimeSeconds: Int) {
        logColored(String(repeating: "=", count: 50), color: .blue)
        logColored("Phased Implementation Automation", color: .blue)
        logColored(String(repeating: "=", count: 50), color: .blue)
        log("Planning document: \(ANSIColor.green.rawValue)\(planPath.path)\(ANSIColor.reset.rawValue)")
        log("Max runtime: \(ANSIColor.green.rawValue)\(TimerDisplay.formatTime(maxRuntimeSeconds))\(ANSIColor.reset.rawValue)")
        logColored(String(repeating: "=", count: 50), color: .blue)
        log("")
    }

    private func printPhaseOverview(phases: [PhaseStatus]) {
        log("")
        logColored(String(repeating: "=", count: 50), color: .blue)
        logColored("Implementation Steps", color: .blue)
        logColored(String(repeating: "=", count: 50), color: .blue)
        log("Total steps: \(ANSIColor.green.rawValue)\(phases.count)\(ANSIColor.reset.rawValue)\n")

        for (i, phase) in phases.enumerated() {
            let color: ANSIColor = phase.isCompleted ? .green : .yellow
            log("  \(color.rawValue)\(i + 1): \(phase.description)\(ANSIColor.reset.rawValue)")
        }

        logColored(String(repeating: "=", count: 50), color: .blue)
        log("")
    }

    private func printSeparator() {
        logColored(String(repeating: "=", count: 50), color: .blue)
    }

    private func printDivider() {
        logColored(String(repeating: "-", count: 50), color: .blue)
    }
}
