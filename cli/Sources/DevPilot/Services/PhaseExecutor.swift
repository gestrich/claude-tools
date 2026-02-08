import Foundation

struct PhaseExecutor {
    let claudeService: ClaudeService

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

    func execute(planPath: URL, repoPath: URL?, maxMinutes: Int, worktreeService: WorktreeService? = nil) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: planPath.path) else {
            throw Error.planNotFound(planPath.path)
        }

        let maxRuntimeSeconds = maxMinutes * 60
        let scriptStart = Date()
        let timer = TimerDisplay(maxRuntimeSeconds: maxRuntimeSeconds, scriptStartTime: scriptStart)

        printHeader(planPath: planPath, maxRuntimeSeconds: maxRuntimeSeconds)

        printColored("Fetching phase information...", color: .cyan)
        var statusResponse: PhaseStatusResponse = try await getPhaseStatus(planPath: planPath, repoPath: repoPath)
        var phases = statusResponse.phases
        var nextIndex = statusResponse.nextPhaseIndex

        printPhaseOverview(phases: phases)

        if nextIndex == -1 {
            printColored("All steps already complete!", color: .green)
            return
        }

        printColored("Starting from Step \(nextIndex + 1): \(phases[nextIndex].description)\n", color: .cyan)

        var phasesExecuted = 0

        while nextIndex != -1 {
            let elapsed = Date().timeIntervalSince(scriptStart)
            if Int(elapsed) >= maxRuntimeSeconds {
                printColored("Time limit reached (\(TimerDisplay.formatTime(maxRuntimeSeconds)))", color: .yellow)
                break
            }

            let phase = phases[nextIndex]
            let totalSteps = phases.count

            printSeparator()
            printColored("Step \(nextIndex + 1) of \(totalSteps) -> \(phase.description)", color: .yellow)
            printDivider()
            printColored("Running claude...\n", color: .blue)

            let phaseStart = Date()

            do {
                let result = try await executePhase(
                    planPath: planPath,
                    phaseIndex: nextIndex,
                    description: phase.description,
                    repoPath: repoPath,
                    timer: timer
                )

                let phaseElapsed = Int(Date().timeIntervalSince(phaseStart))
                let totalElapsed = Int(Date().timeIntervalSince(scriptStart))

                if !result.success {
                    printColored("\nStep \(nextIndex + 1) reported failure", color: .red)
                    printColored("⏱  Step time: \(TimerDisplay.formatTime(phaseElapsed)) | Total: \(TimerDisplay.formatTime(totalElapsed))", color: .cyan)
                    throw Error.phaseFailed(nextIndex, phase.description)
                }

                printColored("\nStep \(nextIndex + 1) completed successfully", color: .green)
                printColored("⏱  Step time: \(TimerDisplay.formatTime(phaseElapsed)) | Total: \(TimerDisplay.formatTime(totalElapsed))", color: .cyan)
                printDivider()
                print()

            } catch let error as ClaudeService.Error {
                let phaseElapsed = Int(Date().timeIntervalSince(phaseStart))
                let totalElapsed = Int(Date().timeIntervalSince(scriptStart))
                printColored("\nPhase \(nextIndex + 1) failed: \(error.localizedDescription)", color: .red)
                printColored("⏱  Phase time: \(TimerDisplay.formatTime(phaseElapsed)) | Total: \(TimerDisplay.formatTime(totalElapsed))", color: .cyan)
                throw Error.phaseFailed(nextIndex, phase.description)
            }

            phasesExecuted += 1

            // Re-read status (handles dynamic phase generation from Phase 3)
            printColored("Fetching updated phase status...", color: .cyan)
            statusResponse = try await getPhaseStatus(planPath: planPath, repoPath: repoPath)
            phases = statusResponse.phases
            nextIndex = statusResponse.nextPhaseIndex

            if nextIndex != -1 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        // Final summary
        let totalTime = Int(Date().timeIntervalSince(scriptStart))
        printSeparator()

        if nextIndex == -1 {
            printColored("✓ All steps completed successfully!", color: .green)
        } else {
            let remaining = phases.filter { !$0.isCompleted }.count
            printColored("Time limit reached — \(remaining) steps may remain", color: .yellow)
        }

        printSeparator()
        printColored("Total steps executed: \(phasesExecuted)", color: .green)
        printColored("Total time: \(TimerDisplay.formatTime(totalTime))", color: .cyan)
        printColored("Planning document: \(planPath.path)", color: .green)
        print()

        if nextIndex == -1 {
            moveToCompleted(planPath: planPath)
            playCompletionSound()

            // Clean up worktree after successful completion
            if let worktreeService = worktreeService, let repoPath = repoPath {
                print()
                Self.printColored("Cleaning up worktree...", color: .cyan)
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

    private func getPhaseStatus(planPath: URL, repoPath: URL?) async throws -> PhaseStatusResponse {
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
            workingDirectory: repoPath
        )
    }

    private func executePhase(
        planPath: URL,
        phaseIndex: Int,
        description: String,
        repoPath: URL?,
        timer: TimerDisplay
    ) async throws -> PhaseResult {
        let prompt = """
        Look at \(planPath.path) for background.

        You are working on Phase \(phaseIndex + 1): \(description)

        Complete ONLY this phase by:
        1. Implementing the required changes
        2. Ensuring the build succeeds
        3. Updating the markdown document to mark this phase as completed with any relevant technical notes
        4. Committing your changes

        Return success: true if the phase was completed successfully, false otherwise.
        """

        timer.start()
        defer { timer.stop() }

        return try await claudeService.call(
            prompt: prompt,
            jsonSchema: Self.executionSchema,
            workingDirectory: repoPath
        )
    }

    // MARK: - Interactive Plan Selection

    static func selectPlanningDoc(proposedDir: String = "docs/proposed") -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: proposedDir) else {
            Self.printColored("Error: Directory not found: \(proposedDir)", color: .red)
            return nil
        }

        let dirURL = URL(fileURLWithPath: proposedDir)
        guard let contents = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            Self.printColored("Error: Could not read \(proposedDir)", color: .red)
            return nil
        }

        let mdFiles = Array(contents
            .filter { $0.pathExtension == "md" }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return aDate > bDate
            }
            .prefix(5))

        guard !mdFiles.isEmpty else {
            Self.printColored("Error: No .md files found in \(proposedDir)", color: .red)
            return nil
        }

        Self.printColored("No planning document specified.", color: .blue)
        print("Last \(ANSIColor.green.rawValue)\(mdFiles.count)\(ANSIColor.reset.rawValue) modified files in \(ANSIColor.green.rawValue)\(proposedDir)\(ANSIColor.reset.rawValue):\n")

        for (i, file) in mdFiles.enumerated() {
            print("  \(ANSIColor.yellow.rawValue)\(i + 1)\(ANSIColor.reset.rawValue)) \(file.lastPathComponent)")
        }

        print()
        Swift.print("Select a file to implement [1-\(mdFiles.count)] (default: 1): ", terminator: "")

        let input = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
        let selection = input.isEmpty ? "1" : input

        guard let idx = Int(selection), idx >= 1, idx <= mdFiles.count else {
            Self.printColored("Invalid selection.", color: .red)
            return nil
        }

        return mdFiles[idx - 1]
    }

    // MARK: - Completion Handling

    private func moveToCompleted(planPath: URL) {
        let fm = FileManager.default
        let completedDir = planPath.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("completed")

        do {
            if !fm.fileExists(atPath: completedDir.path) {
                try fm.createDirectory(at: completedDir, withIntermediateDirectories: true)
            }

            let destPath = completedDir.appendingPathComponent(planPath.lastPathComponent)
            try fm.moveItem(at: planPath, to: destPath)
            Self.printColored("Moved spec to \(destPath.path)", color: .green)

            let gitAdd = Process()
            gitAdd.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            gitAdd.arguments = ["git", "add", planPath.path, destPath.path]
            try gitAdd.run()
            gitAdd.waitUntilExit()

            let gitCommit = Process()
            gitCommit.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            gitCommit.arguments = ["git", "commit", "-m", "Move completed spec to docs/completed"]
            try gitCommit.run()
            gitCommit.waitUntilExit()

            Self.printColored("Committed spec move", color: .green)
            print()
        } catch {
            Self.printColored("Could not move spec: \(error.localizedDescription)", color: .yellow)
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

    private static func printColored(_ text: String, color: ANSIColor) {
        print("\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)")
    }

    private func printColored(_ text: String, color: ANSIColor) {
        Self.printColored(text, color: color)
    }

    private func printHeader(planPath: URL, maxRuntimeSeconds: Int) {
        Self.printColored(String(repeating: "=", count: 50), color: .blue)
        Self.printColored("Phased Implementation Automation", color: .blue)
        Self.printColored(String(repeating: "=", count: 50), color: .blue)
        print("Planning document: \(ANSIColor.green.rawValue)\(planPath.path)\(ANSIColor.reset.rawValue)")
        print("Max runtime: \(ANSIColor.green.rawValue)\(TimerDisplay.formatTime(maxRuntimeSeconds))\(ANSIColor.reset.rawValue)")
        Self.printColored(String(repeating: "=", count: 50), color: .blue)
        print()
    }

    private func printPhaseOverview(phases: [PhaseStatus]) {
        print()
        Self.printColored(String(repeating: "=", count: 50), color: .blue)
        Self.printColored("Implementation Steps", color: .blue)
        Self.printColored(String(repeating: "=", count: 50), color: .blue)
        print("Total steps: \(ANSIColor.green.rawValue)\(phases.count)\(ANSIColor.reset.rawValue)\n")

        for (i, phase) in phases.enumerated() {
            let color: ANSIColor = phase.isCompleted ? .green : .yellow
            print("  \(color.rawValue)\(i + 1): \(phase.description)\(ANSIColor.reset.rawValue)")
        }

        Self.printColored(String(repeating: "=", count: 50), color: .blue)
        print()
    }

    private func printSeparator() {
        Self.printColored(String(repeating: "=", count: 50), color: .blue)
    }

    private func printDivider() {
        Self.printColored(String(repeating: "-", count: 50), color: .blue)
    }
}
