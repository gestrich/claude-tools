import Foundation

struct WorktreeService {
    let logService: LogService?

    init(logService: LogService? = nil) {
        self.logService = logService
    }

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

    func createWorktree(repoPath: URL, baseBranch: String, destination: URL) throws -> URL {
        let fm = FileManager.default

        guard fm.fileExists(atPath: repoPath.path) else {
            throw Error.invalidRepoPath(repoPath.path)
        }

        log("Fetching latest changes from remote...")
        do {
            try runGit(["fetch", "origin", baseBranch], workingDirectory: repoPath)
        } catch {
            log("Warning: Could not fetch from remote: \(error.localizedDescription)")
        }

        log("Creating worktree at \(destination.path)...")
        try runGit(
            ["worktree", "add", destination.path, "origin/\(baseBranch)"],
            workingDirectory: repoPath
        )

        log("Worktree created successfully at \(destination.path)")
        return destination
    }

    func removeWorktree(worktreePath: URL) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: worktreePath.path) else {
            return
        }

        log("Removing worktree at \(worktreePath.path)...")

        let gitFile = worktreePath.appendingPathComponent(".git")
        guard let gitContent = try? String(contentsOf: gitFile, encoding: .utf8),
              gitContent.hasPrefix("gitdir: ") else {
            throw Error.worktreeRemovalFailed("Could not find main repository reference")
        }

        let gitdirPath = gitContent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "gitdir: ", with: "")

        let mainRepoGitDir = URL(fileURLWithPath: gitdirPath, relativeTo: worktreePath)
            .standardizedFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        do {
            try runGit(["worktree", "remove", worktreePath.path, "--force"], workingDirectory: mainRepoGitDir)
        } catch {
            log("Warning: git worktree remove failed, attempting manual cleanup: \(error.localizedDescription)")
            try? fm.removeItem(at: worktreePath)
            try? runGit(["worktree", "prune"], workingDirectory: mainRepoGitDir)
        }

        log("Worktree removed successfully")
    }

    // MARK: - Private

    private func log(_ message: String) {
        if let logService {
            logService.log(message)
        } else {
            print(message)
        }
    }

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
