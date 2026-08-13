import Foundation

/// Runs the `claude` CLI (uses the session / subscription already authenticated locally).
enum ClaudeRunner {

    enum RunError: LocalizedError {
        case cliNotFound
        case timedOut
        case failed(String)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .cliNotFound:
                return "Could not find the `claude` binary on this system."
            case .timedOut:
                return "The request took too long (timeout)."
            case .failed(let message):
                return message.isEmpty ? "The CLI returned an error." : message
            case .emptyOutput:
                return "Empty response."
            }
        }
    }

    private static let systemPrompt = """
    You are a text rewriter. Output ONLY the rewritten text, nothing else: \
    no preamble, no explanation, no commentary, no surrounding quotes, no markdown fences. \
    Always preserve the original language of the input. \
    Preserve the author's meaning, tone and register; do not add or remove information.
    """

    private static let userPrompt = """
    Improve the grammar, spelling, punctuation and syntax of the text provided by the user, \
    making it read naturally and correctly.
    """

    /// Locates the `claude` binary. The app can be launched from Finder, where PATH
    /// includes neither Homebrew nor the local installers, so we try known paths and
    /// fall back to the login shell only as a last resort.
    private static func resolveCLI() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.local/bin/claude",
            "\(home)/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/bin/zsh")
        which.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice
        do {
            try which.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            which.waitUntilExit()
            let path = String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .last
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            return nil
        }
        return nil
    }

    static func improve(_ text: String, model: String = "opus", timeout: TimeInterval = 90) throws -> String {
        guard let cli = resolveCLI() else { throw RunError.cliNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = [
            "-p",
            "--model", model,
            "--output-format", "text",
            // No user settings: keeps CLAUDE.md and other global rules from
            // changing the language or adding preambles to the response.
            "--setting-sources", "",
            "--strict-mcp-config",
            "--system-prompt", systemPrompt,
            userPrompt,
        ]

        // Empty directory so no project's CLAUDE.md gets loaded.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyntaxFixer", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = workDir

        var env = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = env["PATH"].map { "\($0):\(extraPath)" } ?? extraPath
        process.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        stdin.fileHandleForWriting.write(Data(text.utf8))
        try? stdin.fileHandleForWriting.close()

        // Read in the background so a full pipe can't block us.
        var outData = Data()
        var errData = Data()
        let queue = DispatchQueue(label: "syntaxfixer.read")
        let group = DispatchGroup()
        group.enter()
        queue.async {
            outData = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        queue.async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            throw RunError.timedOut
        }
        process.waitUntilExit()
        group.wait()

        let output = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let errors = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            throw RunError.failed(errors.isEmpty ? output : errors)
        }
        guard !output.isEmpty else { throw RunError.emptyOutput }
        return output
    }
}
