import Foundation

struct WorktreeService {
    enum Error: Swift.Error, LocalizedError {
        case gitCommandFailed(String, Int32, String)
        case worktreeCreationFailed(String)
        case worktreeRemovalFailed(String)
        case invalidRepoPath(String)

        var errorDescription: String? {
            switch self {
            case .gitCommandFailed(let command, let exitCode, let stderr):
                return "Git command '\(command)' failed with exit code \(exitCode): \(stderr)"
            case .worktreeCreationFailed(let detail):
                return "Failed to create worktree: \(detail)"
            case .worktreeRemovalFailed(let detail):
                return "Failed to remove worktree: \(detail)"
            case .invalidRepoPath(let path):
                return "Invalid repository path: \(path)"
            }
        }
    }

    /// Creates a worktree in ~/Desktop/worktrees/<repo name>/<timestamp>
    /// - Parameters:
    ///   - repoPath: Path to the main repository
    ///   - baseBranch: Branch to base the worktree on
    /// - Returns: URL of the created worktree
    func createWorktree(repoPath: URL, baseBranch: String) throws -> URL {
        let fm = FileManager.default

        // Verify repo path exists
        guard fm.fileExists(atPath: repoPath.path) else {
            throw Error.invalidRepoPath(repoPath.path)
        }

        let repoName = repoPath.lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")

        // Create worktree directory: ~/Desktop/worktrees/<repo name>/<timestamp>
        let worktreesBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("worktrees")
            .appendingPathComponent(repoName)

        if !fm.fileExists(atPath: worktreesBase.path) {
            try? fm.createDirectory(at: worktreesBase, withIntermediateDirectories: true)
        }

        let worktreePath = worktreesBase.appendingPathComponent(timestamp)

        // Fetch latest from remote
        print("Fetching latest changes from remote...")
        do {
            try runGit(["fetch", "origin", baseBranch], workingDirectory: repoPath)
        } catch {
            // Continue even if fetch fails (might be offline)
            print("Warning: Could not fetch from remote: \(error.localizedDescription)")
        }

        // Create worktree
        print("Creating worktree at \(worktreePath.path)...")
        try runGit(
            ["worktree", "add", worktreePath.path, "origin/\(baseBranch)"],
            workingDirectory: repoPath
        )

        print("✓ Worktree created successfully at \(worktreePath.path)")
        return worktreePath
    }

    /// Removes a worktree and cleans up the directory
    /// - Parameter worktreePath: Path to the worktree to remove
    func removeWorktree(worktreePath: URL) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: worktreePath.path) else {
            // Already removed
            return
        }

        print("Removing worktree at \(worktreePath.path)...")

        // Get the main repo path by finding .git file in worktree (it's a link to the main repo)
        let gitFile = worktreePath.appendingPathComponent(".git")
        guard let gitContent = try? String(contentsOf: gitFile, encoding: .utf8),
              gitContent.hasPrefix("gitdir: ") else {
            throw Error.worktreeRemovalFailed("Could not find main repository reference")
        }

        // Parse gitdir path to find main repo
        let gitdirPath = gitContent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "gitdir: ", with: "")

        let mainRepoGitDir = URL(fileURLWithPath: gitdirPath, relativeTo: worktreePath)
            .standardizedFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        // Run git worktree remove from the main repo
        do {
            try runGit(["worktree", "remove", worktreePath.path, "--force"], workingDirectory: mainRepoGitDir)
        } catch {
            print("Warning: git worktree remove failed, attempting manual cleanup: \(error.localizedDescription)")

            // Fallback: manually delete the directory
            try? fm.removeItem(at: worktreePath)

            // Prune worktree list
            try? runGit(["worktree", "prune"], workingDirectory: mainRepoGitDir)
        }

        print("✓ Worktree removed successfully")
    }

    // MARK: - Git Command Runner

    private func runGit(_ args: [String], workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw Error.gitCommandFailed(
                "git \(args.joined(separator: " "))",
                process.terminationStatus,
                stderr
            )
        }
    }
}
