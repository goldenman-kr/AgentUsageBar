import Foundation

public enum CodexStatusCommand {
    private static let prompt = "Reply with exactly: OK"

    public static func refresh(timeout: TimeInterval = 20) async throws {
        guard let executableURL = findCodexExecutable() else {
            throw UsageError.network("Codex CLI를 찾을 수 없습니다.")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "exec",
            "--json",
            "--skip-git-repo-check",
            "--ignore-rules",
            "--ignore-user-config",
            "-s", "read-only",
            prompt
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let stdin = Pipe()
        let output = Pipe()
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = output

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await run(process: process, stdin: stdin)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
                throw UsageError.network("Codex status 갱신 명령 시간이 초과되었습니다.")
            }

            try await group.next()
            group.cancelAll()
        }

        // The CLI writes the rate-limit event near process completion; give the
        // log writer a short moment before the caller re-reads SQLite.
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    static func findCodexExecutable() -> URL? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for dir in paths {
            let path = URL(fileURLWithPath: dir).appendingPathComponent("codex").path
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func run(process: Process, stdin: Pipe) async throws {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UsageError.network(
                        "Codex status 갱신 명령 실패 (exit \(process.terminationStatus))"
                    ))
                }
            }

            do {
                try process.run()
                stdin.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(throwing: UsageError.network(error.localizedDescription))
            }
        }
    }
}
