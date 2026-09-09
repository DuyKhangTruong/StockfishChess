//
//  StockfishProcess.swift
//  StockfishChess
//

import Foundation

enum StockfishProcessError: LocalizedError {
    case notExecutable(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notExecutable(let path):
            return "\"\((path as NSString).lastPathComponent)\" isn't an executable file. Pick the compiled binary itself — usually the file just named \"stockfish\", with no extension."
        case .launchFailed(let message):
            return message
        }
    }
}

/// Owns the actual OS process. Feeds it commands over stdin, and turns its
/// stdout into a line-by-line AsyncStream. Nothing UCI-specific happens
/// here — that's `EngineManager`'s job.
///
/// This target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a
/// plain class would be main-actor isolated. That is exactly wrong here: the
/// stdout readability handler fires on a *background* queue, so main-actor
/// state would be mutated off the main thread. The type is therefore
/// explicitly `nonisolated` and guards every stored property with `lock`.
nonisolated final class StockfishProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "StockfishProcess.stdin")

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var buffer = Data()
    private var continuation: AsyncStream<String>.Continuation?

    /// Set only if we successfully started security-scoped access for this
    /// URL, so teardown knows whether it needs to release it.
    private var securityScopedURL: URL?

    func launch(url: URL) throws -> AsyncStream<String> {
        // .fileImporter hands back a security-scoped URL, so claim access
        // before touching the file. Note this grants *read* access only —
        // executing a picked binary additionally requires the App Sandbox to
        // be off (ENABLE_APP_SANDBOX = NO); a sandboxed app gets
        // "file doesn't exist" from Process.run() no matter what it picks.
        let startedAccess = url.startAccessingSecurityScopedResource()

        let process = Process()
        process.executableURL = url

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe() // discard engine stderr chatter

        // The AsyncStream builder runs synchronously, so `continuation` is in
        // place before the reader below can possibly fire.
        let stream = AsyncStream<String>(bufferingPolicy: .unbounded) { continuation in
            lock.withLock { self.continuation = continuation }
        }

        lock.withLock {
            self.process = process
            self.stdinHandle = stdinPipe.fileHandleForWriting
            self.stdoutHandle = stdoutPipe.fileHandleForReading
            self.securityScopedURL = startedAccess ? url : nil
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                self.finish() // EOF — the engine closed its output
            } else {
                self.ingest(data)
            }
        }

        // If the engine dies on its own, close the stream so whoever is
        // awaiting a reply gets unblocked instead of hanging forever.
        process.terminationHandler = { [weak self] _ in
            self?.finish()
        }

        do {
            try process.run()
        } catch {
            let nsError = error as NSError
            // Drop the never-launched Process: leaving it stored would make a
            // later terminate() call -[NSConcreteTask terminate] on a task that
            // was never started, which throws NSInvalidArgumentException.
            lock.withLock {
                self.process = nil
                self.stdinHandle = nil
            }
            finish()
            releaseAccess()
            // Don't pre-flight this with FileManager.isExecutableFile: inside an
            // app bundle it reports false for a perfectly runnable binary, and
            // gating on it refuses engines that actually start. Let exec decide,
            // then translate the errno into something a human can act on.
            //   EACCES (13) — not marked executable, or unreadable
            //   ENOEXEC (8) — not a runnable binary at all (a .zip, a folder…)
            if nsError.domain == NSPOSIXErrorDomain, nsError.code == 13 || nsError.code == 8 {
                throw StockfishProcessError.notExecutable(url.path)
            }
            throw StockfishProcessError.launchFailed(
                "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
            )
        }
        return stream
    }

    func send(_ command: String) {
        guard let data = (command + "\n").data(using: .utf8) else { return }
        guard let handle = lock.withLock({ stdinHandle }) else { return }
        // A pipe write blocks once the engine's input buffer fills, and every
        // caller here is on the main actor — so hand it to a serial queue,
        // which also preserves UCI command order.
        writeQueue.async {
            try? handle.write(contentsOf: data)
        }
    }

    /// Safe to call at any time, including on an engine that never started or
    /// has already been torn down.
    func terminate() {
        // Clear state up front so a second call is a no-op.
        let (process, stdin) = lock.withLock {
            let process = self.process
            let stdin = self.stdinHandle
            self.process = nil
            self.stdinHandle = nil
            return (process, stdin)
        }

        if let process {
            process.terminationHandler = nil
            // `terminate()` raises on a task that was never launched, and
            // `isRunning` is the only way to tell the two apart.
            if process.isRunning {
                // Written synchronously: an async write would race the kill.
                // `quit` lets Stockfish shut down on its own terms.
                try? stdin?.write(contentsOf: Data("quit\n".utf8))
                process.terminate()
            }
        }

        finish()
        releaseAccess()
    }

    // MARK: - Reading

    private func ingest(_ data: Data) {
        let lines: [String] = lock.withLock {
            buffer.append(data)
            var out: [String] = []
            while let index = buffer.firstIndex(of: 0x0A) {
                let lineData = Data(buffer[buffer.startIndex..<index])
                buffer.removeSubrange(buffer.startIndex...index)
                if let line = String(data: lineData, encoding: .utf8) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { out.append(trimmed) }
                }
            }
            return out
        }
        guard !lines.isEmpty else { return }
        // Yield outside the lock — the consumer calls straight back into send().
        let continuation = lock.withLock { self.continuation }
        for line in lines { continuation?.yield(line) }
    }

    /// Idempotent: detaches the reader and closes the stream exactly once.
    private func finish() {
        let (continuation, stdout) = lock.withLock {
            let c = self.continuation
            let s = self.stdoutHandle
            self.continuation = nil
            self.stdoutHandle = nil
            return (c, s)
        }
        stdout?.readabilityHandler = nil
        continuation?.finish()
    }

    private func releaseAccess() {
        let url = lock.withLock {
            let u = securityScopedURL
            securityScopedURL = nil
            return u
        }
        url?.stopAccessingSecurityScopedResource()
    }
}
