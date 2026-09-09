import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var game = ChessGame()
    @StateObject private var engine = EngineManager()

    @AppStorage("stockfishBookmark") private var stockfishBookmark: Data = Data()
    @AppStorage("stockfishDisplayPath") private var stockfishDisplayPath: String = ""
    @State private var showPathPicker = false
    @State private var bookmarkError: String? = nil

    @State private var mode: ControlsView.Mode = .analysis
    @State private var orientation: PieceColor = .white
    @State private var depth: Double = 16
    @State private var multipv: Double = 3
    @State private var skill: Double = 12
    @State private var movetimeMs: Double = 800
    @State private var playerColor: PieceColor = .white

    @State private var searchTask: Task<Void, Never>? = nil
    @State private var launchTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if stockfishBookmark.isEmpty || isEngineError {
                pathPrompt
            } else {
                HStack(alignment: .top, spacing: 24) {
                    HStack(alignment: .top, spacing: 14) {
                        EvalBarView(score: engine.lines.first?.score, orientation: orientation)
                        BoardView(
                            game: game,
                            orientation: orientation,
                            arrow: analysisArrow,
                            interactive: interactive,
                            onMove: { from, to in game.makeMove(from: from, to: to) }
                        )
                    }
                    .frame(maxWidth: 600)

                    VStack(spacing: 14) {
                        AnalysisPanelView(
                            engine: engine,
                            fen: game.fen,
                            onPlayLine: game.atLatest ? { game.applyUCI($0) } : nil
                        )
                        MoveListView(game: game)
                        ControlsView(
                            mode: $mode, depth: $depth, multipv: $multipv, skill: $skill,
                            movetimeMs: $movetimeMs, playerColor: $playerColor,
                            onNewGame: { Task { await engine.newGame(); game.reset() } },
                            onUndo: game.undo,
                            onFlip: { orientation = orientation == .white ? .black : .white },
                            onGoTo: game.goTo,
                            cursor: game.cursor,
                            lastPly: game.sanMoves.count,
                            fen: game.fen,
                            pgn: game.pgn,
                            onLoadFEN: game.loadFEN
                        )
                    }
                    .frame(width: 330)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 980, minHeight: 720)
        .background(Theme.ink.ignoresSafeArea())
        .foregroundStyle(Theme.bone)
        .onAppear { launchEngineIfNeeded() }
        .onDisappear { engine.shutdown() }
        .onChange(of: skill) { newValue in if mode == .play { engine.setSkillLevel(Int(newValue)) } }
        .onChange(of: game.fen) { _ in scheduleSearch() }
        .onChange(of: mode) { _ in scheduleSearch() }
        .onChange(of: depth) { _ in scheduleSearch() }
        .onChange(of: multipv) { _ in scheduleSearch() }
        .onChange(of: playerColor) { _ in scheduleSearch() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Analysis Desk")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                if !stockfishBookmark.isEmpty {
                    Button("Change engine…") { showPathPicker = true }
                        .buttonStyle(.bordered)
                        .font(.system(size: 12))
                }
            }
            HStack(spacing: 6) {
                Text("Stockfish, reading over your shoulder ·")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
                Text(statusLabel)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.brass)
                if !stockfishDisplayPath.isEmpty {
                    Text("· \(stockfishDisplayPath)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .fileImporter(
            isPresented: $showPathPicker,
            allowedContentTypes: [.data],
            onCompletion: { result in
                switch result {
                case .success(let url):
                    let didStartAccess = url.startAccessingSecurityScopedResource()
                    defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

                    // Sanity checks before we even try to bookmark it, so the
                    // error we show (and log) points at the real problem.
                    var isDirectory: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    let isExecutable = FileManager.default.isExecutableFile(atPath: url.path)
                    print("[engine-pick] path=\(url.path) exists=\(exists) isDirectory=\(isDirectory.boolValue) isExecutable=\(isExecutable) startedAccess=\(didStartAccess)")

                    do {
                        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                        stockfishBookmark = bookmark
                        stockfishDisplayPath = url.path
                        bookmarkError = nil
                        launchEngineIfNeeded(force: true)
                    } catch {
                        let nsError = error as NSError
                        print("[engine-pick] bookmarkData failed: domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")
                        bookmarkError = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
                    }
                case .failure(let error):
                    let nsError = error as NSError
                    print("[engine-pick] fileImporter failed: domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")
                    bookmarkError = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
                }
            }
        )
    }

    private var statusLabel: String {
        switch engine.status {
        case .idle: return "idle"
        case .launching: return "launching"
        case .ready: return engine.thinking ? "thinking" : "idle"
        case .error: return "error"
        }
    }

    private var isEngineError: Bool {
        if case .error = engine.status { return true }
        return false
    }

    private var pathPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bookmarkError {
                Text("Couldn't use that file: \(bookmarkError)")
                    .foregroundStyle(Theme.rust)
            } else if case .error(let message) = engine.status {
                Text("That binary didn't start: \(message)")
                    .foregroundStyle(Theme.rust)
                Text("Pick the actual compiled binary — usually the file just named \"stockfish\" with no extension, inside the src/ folder where you built it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("Point this at your compiled Stockfish binary to get started.")
                    .foregroundStyle(Theme.boneDim)
            }
            Button("Choose Stockfish binary…") { showPathPicker = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brass)
        }
    }

    private var interactive: Bool {
        !game.isGameOver && game.atLatest && (mode == .analysis || game.turn == playerColor)
    }

    private var analysisArrow: (from: Int, to: Int)? {
        guard mode == .analysis,
              let first = engine.lines.first?.pv.first,
              first.count >= 4,
              let from = Square.fromAlgebraic(String(first.prefix(2))),
              let to = Square.fromAlgebraic(String(first.dropFirst(2).prefix(2)))
        else { return nil }
        return (from, to)
    }

    private func resolvedEngineURL() -> URL? {
        guard !stockfishBookmark.isEmpty else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: stockfishBookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            if let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                stockfishBookmark = refreshed
            }
        }
        return url
    }

    private func launchEngineIfNeeded(force: Bool = false) {
        guard let url = resolvedEngineURL(), force || engine.status == .idle else { return }
        launchTask?.cancel()
        launchTask = Task {
            await engine.launch(url: url)
            scheduleSearch()
        }
    }

    private func scheduleSearch() {
        guard engine.status == .ready else { return }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000) // debounce rapid clicks
            guard !Task.isCancelled else { return }

            if mode == .analysis {
                guard !game.isGameOver else { return }
                _ = await engine.analyze(.init(fen: game.fen, turn: game.turn, depthLimit: Int(depth), multipv: Int(multipv)))
            } else {
                guard !game.isGameOver, game.atLatest, game.turn != playerColor else { return }
                let result = await engine.analyze(.init(fen: game.fen, turn: game.turn, movetime: Int(movetimeMs), multipv: 1))
                if !Task.isCancelled, let best = result.bestmove {
                    game.applyUCI(best)
                }
            }
        }
    }
}
