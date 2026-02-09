import Foundation

struct PlanGenerator {
    let claudeService: ClaudeService
    let logService: LogService?

    init(claudeService: ClaudeService, logService: LogService? = nil) {
        self.claudeService = claudeService
        self.logService = logService
    }

    enum Error: Swift.Error, LocalizedError {
        case noMatchingRepo(String)
        case repoNotFound(String)
        case writeError(String)

        var errorDescription: String? {
            switch self {
            case .noMatchingRepo(let detail):
                return "No matching repository: \(detail)"
            case .repoNotFound(let id):
                return "Repository '\(id)' not found in repos.json"
            case .writeError(let detail):
                return "Failed to write plan: \(detail)"
            }
        }
    }

    func generate(voiceText: String, repos: ReposConfig) async throws -> (URL, Repository) {
        log("Step 1/3: Matching repository...")
        let repoMatch: RepoMatch = try await matchRepo(voiceText: voiceText, repos: repos)
        log("Matched repository: \(repoMatch.repoId)")
        log("Interpreted request: \(repoMatch.interpretedRequest)")

        guard let repo = repos.repository(withId: repoMatch.repoId) else {
            throw Error.repoNotFound(repoMatch.repoId)
        }

        log("Step 2/3: Generating implementation plan...")
        let plan: GeneratedPlan = try await generatePlan(
            interpretedRequest: repoMatch.interpretedRequest,
            repo: repo
        )
        log("Generated plan: \(plan.filename)")

        log("Step 3/3: Writing plan to disk...")
        let planURL = try writePlan(plan, repo: repo)
        log("Plan written to: \(planURL.path)")

        return (planURL, repo)
    }

    private func matchRepo(voiceText: String, repos: ReposConfig) async throws -> RepoMatch {
        let repoList = repos.repositories.map { repo in
            var entry = "- id: \(repo.id) | description: \(repo.description)"
            if let focus = repo.recentFocus {
                entry += " | recent focus: \(focus)"
            }
            return entry
        }.joined(separator: "\n")

        let prompt = """
        You are helping match a voice-transcribed development request to the correct repository.

        The voice transcription likely has errors — use the repository descriptions and recent focus areas to infer the best match.

        Voice text: "\(voiceText)"

        Available repositories:
        \(repoList)

        Return the best matching repository ID and your interpretation of what the request is actually asking for (correcting any likely transcription errors).
        """

        let schema = """
        {"type":"object","properties":{"repoId":{"type":"string","description":"The id of the matched repository"},"interpretedRequest":{"type":"string","description":"The corrected/interpreted version of the voice request"}},"required":["repoId","interpretedRequest"]}
        """

        return try await claudeService.call(prompt: prompt, jsonSchema: schema, logService: logService, needsTools: false)
    }

    private func generatePlan(interpretedRequest: String, repo: Repository) async throws -> GeneratedPlan {
        let repoContext = """
        Repository: \(repo.id)
        Path: \(repo.path)
        Description: \(repo.description)
        Skills: \(repo.skills.joined(separator: ", "))
        Architecture docs: \(repo.architectureDocs.joined(separator: ", "))
        Verification commands: \(repo.verification.commands.joined(separator: ", "))
        PR base branch: \(repo.pullRequest.baseBranch)
        Branch naming: \(repo.pullRequest.branchNamingConvention)
        """

        let prompt = """
        You are generating a phased implementation plan document. You are ONLY generating the plan skeleton — do NOT execute, explore, or implement anything.

        Request: "\(interpretedRequest)"

        Repository context:
        \(repoContext)

        Generate a markdown plan document with EXACTLY this structure:

        1. A title (## heading) based on the request
        2. A "Background" section briefly describing what needs to be done
        3. Exactly three phases, all unchecked:

        ## - [ ] Phase 1: Interpret the Request
        When executed, this phase will explore the codebase and recent commits (authored by Bill Gestrich) to understand what the voice transcription is asking for. It will find the relevant code, files, and areas. This phase is purely about understanding — no implementation planning yet. The voice text may have transcription errors; use recent commits and codebase context to infer intent. Document findings underneath this phase heading.

        ## - [ ] Phase 2: Gather Architectural Guidance
        When executed, this phase will look at the repository's skills (\(repo.skills.joined(separator: ", "))) and architecture docs (\(repo.architectureDocs.joined(separator: ", "))) to identify which documentation and architectural guidelines are relevant to this request. It will read and summarize the key constraints. Document findings underneath this phase heading.

        ## - [ ] Phase 3: Plan the Implementation
        When executed, this phase will use insights from Phases 1 and 2 to create concrete implementation steps. It will append new phases (Phase 4 through N) to this document, each with: what to implement, which files to modify, which architectural documents to reference, and acceptance criteria. It will also append a Testing/Verification phase and a Create Pull Request phase at the end. This phase is responsible for generating the remaining phases dynamically.

        No Phase 4+ should be included — Phase 3 will generate them when executed.

        All phases must be unchecked (- [ ]). None are completed at this stage.

        Also generate a filename for this plan (kebab-case, no extension, descriptive of the request).

        Return the full markdown content as planContent and the filename as filename.
        """

        let schema = """
        {"type":"object","properties":{"planContent":{"type":"string","description":"The full markdown plan document content"},"filename":{"type":"string","description":"Kebab-case filename without extension"}},"required":["planContent","filename"]}
        """

        return try await claudeService.call(
            prompt: prompt,
            jsonSchema: schema,
            workingDirectory: URL(fileURLWithPath: repo.path),
            logService: logService,
            needsTools: false
        )
    }

    private func writePlan(_ plan: GeneratedPlan, repo: Repository) throws -> URL {
        let docsDir = URL(fileURLWithPath: repo.path)
            .appendingPathComponent("docs")
            .appendingPathComponent("proposed")

        let fm = FileManager.default
        if !fm.fileExists(atPath: docsDir.path) {
            do {
                try fm.createDirectory(at: docsDir, withIntermediateDirectories: true)
            } catch {
                throw Error.writeError("Could not create docs/proposed/ directory: \(error.localizedDescription)")
            }
        }

        let filename = plan.filename.hasSuffix(".md") ? plan.filename : "\(plan.filename).md"
        let fileURL = docsDir.appendingPathComponent(filename)

        do {
            try plan.planContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw Error.writeError("Could not write plan file: \(error.localizedDescription)")
        }

        return fileURL
    }

    private func log(_ message: String) {
        if let logService {
            logService.log(message)
        } else {
            print(message)
        }
    }
}
