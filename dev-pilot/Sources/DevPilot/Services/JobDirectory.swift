import Foundation

struct JobDirectory {
    let url: URL

    var planURL: URL { url.appendingPathComponent("plan.md") }
    var worktreeURL: URL { url.appendingPathComponent("worktree") }

    func logURL(label: String) -> URL {
        url.appendingPathComponent("\(label).log")
    }

    static var baseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("dev-pilot")
    }

    static func create(repoId: String, jobName: String) throws -> JobDirectory {
        let sanitized = String(
            jobName.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                .prefix(80)
        )
        let dirURL = baseURL
            .appendingPathComponent(repoId)
            .appendingPathComponent(sanitized)

        let fm = FileManager.default
        if !fm.fileExists(atPath: dirURL.path) {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        return JobDirectory(url: dirURL)
    }

    static func deriveRepoId(from planPath: URL) -> String? {
        // Expected path: ~/Desktop/dev-pilot/<repo-id>/<job-name>/plan.md
        let components = planPath.pathComponents
        let baseComponents = baseURL.pathComponents

        guard components.count > baseComponents.count + 2,
              components.starts(with: baseComponents) else {
            return nil
        }

        return components[baseComponents.count]
    }

    static func list() -> [JobDirectory] {
        let fm = FileManager.default
        let base = baseURL

        guard fm.fileExists(atPath: base.path),
              let repoDirs = try? fm.contentsOfDirectory(
                  at: base,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var results: [JobDirectory] = []

        for repoDir in repoDirs {
            guard let jobDirs = try? fm.contentsOfDirectory(
                at: repoDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for jobDir in jobDirs {
                let planFile = jobDir.appendingPathComponent("plan.md")
                if fm.fileExists(atPath: planFile.path) {
                    results.append(JobDirectory(url: jobDir))
                }
            }
        }

        return results
    }
}
