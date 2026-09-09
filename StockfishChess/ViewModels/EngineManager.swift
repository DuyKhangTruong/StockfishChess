//
//  EngineManager.swift
//  StockfishChess
//

import Foundation
import Combine

/// The engine as seen by the UI: published lines/stats/status, and async
/// methods for analyze/stop/newGame. Everything UCI-specific — handshakes,
/// line parsing, continuations — is hidden in here.
///
/// Concurrency contract: the engine speaks one conversation at a time. Every
/// method that sends a `go` holds `gate` for the whole exchange, so a reply
/// can never be delivered to the wrong caller, and no continuation is ever
/// overwritten (which would suspend its task forever).
@MainActor
final class EngineManager: ObservableObject {
    enum Status: Equatable {
        case idle, launching, ready, error(String)
    }

    struct EngineLine: Identifiable {
        var id: Int { multipv }
        var multipv: Int
        var score: Score?
        var pv: [String]
    }

    struct AnalyzeOptions {
        var fen: String
        var turn: PieceColor
        var depthLimit: Int? = nil
        var movetime: Int? = nil
        var infinite: Bool = false
        var multipv: Int = 1
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lines: [EngineLine] = []
    @Published private(set) var depth: Int = 0
    @Published private(set) var nps: Int = 0
    @Published private(set) var nodes: Int = 0
    @Published private(set) var timeMs: Int = 0
    @Published private(set) var thinking: Bool = false

    private let process = StockfishProcess()
    private var readTask: Task<Void, Never>?
    private var searching = false
    private var activeTurn: PieceColor = .white

    private var uciOkContinuation: CheckedContinuation<Bool, Never>?
    private var readyContinuations: [CheckedContinuation<Void, Never>] = []
    private var bestMoveContinuation: CheckedContinuation<(bestmove: String?, ponder: String?), Never>?

    /// Serial gate around the engine conversation. `gateWaiters` are resumed
    /// in FIFO order when the holder releases.
    private var gateHeld = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Lifecycle

    func launch(url: URL, threads: Int = 1, hashMB: Int = 64) async {
        guard status != .launching else { return }
        shutdown()
        status = .launching

        do {
            let stream = try process.launch(url: url)
            readTask = Task { [weak self] in
                for await line in stream {
                    self?.handle(line: line)
                }
                self?.engineDidExit()
            }

            guard await waitForUCIOk(seconds: 10) else {
                process.terminate()
                if case .error = status { return } // engineDidExit already explained it
                status = .error("The program started but never answered \"uciok\" — that doesn't look like a UCI engine.")
                return
            }

            setOption("Threads", "\(threads)")
            setOption("Hash", "\(hashMB)")
            await isReady()
            status = .ready
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func shutdown() {
        readTask?.cancel()
        readTask = nil
        process.terminate()
    }

    // MARK: - Options

    func setOption(_ name: String, _ value: String) {
        process.send("setoption name \(name) value \(value)")
    }

    func setSkillLevel(_ level: Int) {
        setOption("Skill Level", "\(level)")
        setOption("UCI_LimitStrength", level < 20 ? "true" : "false")
    }

    // MARK: - Commands

    func newGame() async {
        requestStop()
        await acquireGate()
        defer { releaseGate() }

        process.send("ucinewgame")
        await isReady()
        lines = []
        depth = 0; nps = 0; nodes = 0; timeMs = 0
    }

    @discardableResult
    func analyze(_ options: AnalyzeOptions) async -> (bestmove: String?, ponder: String?) {
        // Nudge any in-flight search to wrap up *before* queueing behind it,
        // otherwise a `go infinite` would keep the gate forever.
        requestStop()
        await acquireGate()
        defer { releaseGate() }

        // A newer request may have superseded us while we waited.
        guard status == .ready, !Task.isCancelled else { return (nil, nil) }

        activeTurn = options.turn
        lines = []
        depth = 0; nps = 0; nodes = 0; timeMs = 0
        thinking = true
        defer { thinking = false }

        setOption("MultiPV", "\(options.multipv)")
        await isReady()
        process.send("position fen \(options.fen)")

        var go = "go"
        if options.infinite { go += " infinite" }
        if let depthLimit = options.depthLimit { go += " depth \(depthLimit)" }
        if let movetime = options.movetime { go += " movetime \(movetime)" }

        searching = true
        let engine = process // capture: the cancellation handler is nonisolated
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<(bestmove: String?, ponder: String?), Never>) in
                self.bestMoveContinuation = continuation
                engine.send(go)
            }
        } onCancel: {
            // Cancelling the Swift task must actually stop the search, or the
            // engine keeps burning cores on a position nobody is looking at.
            engine.send("stop")
        }
    }

    /// Halts the current search and waits for it to actually finish.
    func stop() async {
        requestStop()
        await acquireGate()
        releaseGate()
    }

    /// Non-blocking nudge. Safe to call when nothing is searching — Stockfish
    /// ignores a stray `stop`.
    private func requestStop() {
        guard searching else { return }
        process.send("stop")
    }

    // MARK: - Handshake

    private func waitForUCIOk(seconds: Double) async -> Bool {
        let timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.resumeUCIOk(false)
        }
        defer { timeout.cancel() }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.uciOkContinuation = continuation
            self.process.send("uci")
        }
    }

    private func resumeUCIOk(_ ok: Bool) {
        uciOkContinuation?.resume(returning: ok)
        uciOkContinuation = nil
    }

    private func isReady() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.readyContinuations.append(continuation)
            self.process.send("isready")
        }
    }

    // MARK: - Gate

    private func acquireGate() async {
        while gateHeld {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gateWaiters.append(continuation)
            }
        }
        gateHeld = true
    }

    private func releaseGate() {
        gateHeld = false
        let waiters = gateWaiters
        gateWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    // MARK: - Line handling

    private func handle(line: String) {
        if line == "uciok" {
            resumeUCIOk(true)
            return
        }
        if line == "readyok" {
            let waiting = readyContinuations
            readyContinuations.removeAll()
            for continuation in waiting { continuation.resume() }
            return
        }
        if line.hasPrefix("info ") {
            guard let info = UCI.parseInfoLine(line) else { return }
            var updated = lines
            let entry = EngineLine(
                multipv: info.multipv,
                score: UCI.normalize(info.score, turn: activeTurn),
                pv: info.pv
            )
            if let existing = updated.firstIndex(where: { $0.multipv == info.multipv }) {
                updated[existing] = entry
            } else {
                updated.append(entry)
            }
            lines = updated.sorted { $0.multipv < $1.multipv }
            depth = info.depth ?? depth
            nps = info.nps ?? nps
            nodes = info.nodes ?? nodes
            timeMs = info.time ?? timeMs
            return
        }
        if line.hasPrefix("bestmove") {
            let tokens = line.split(separator: " ").map(String.init)
            let bestmove = tokens.count > 1 && tokens[1] != "(none)" ? tokens[1] : nil
            let ponder = tokens.count > 3 ? tokens[3] : nil
            searching = false
            bestMoveContinuation?.resume(returning: (bestmove, ponder))
            bestMoveContinuation = nil
            return
        }
    }

    /// The stream ended: the engine crashed, was killed, or we terminated it.
    /// Every outstanding continuation must be resumed or its task hangs.
    private func engineDidExit() {
        searching = false
        thinking = false

        resumeUCIOk(false)

        let waiting = readyContinuations
        readyContinuations.removeAll()
        for continuation in waiting { continuation.resume() }

        bestMoveContinuation?.resume(returning: (nil, nil))
        bestMoveContinuation = nil

        if status == .ready || status == .launching {
            status = .error("The engine process exited unexpectedly.")
        }
    }
}
