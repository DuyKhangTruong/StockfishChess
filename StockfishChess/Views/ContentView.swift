import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var game = ChessGame()
    @StateObject private var engine = EngineManager()
    /// The opponent in an engine match. Launched only when that mode is
    /// first opened, from its own binary or — until one is chosen — a second
    /// copy of the main engine.
    @StateObject private var engine2 = EngineManager()

    private enum EngineSlot { case primary, second }

    @AppStorage("stockfishBookmark") private var stockfishBookmark: Data = Data()
    @AppStorage("stockfishDisplayPath") private var stockfishDisplayPath: String = ""
    @AppStorage("engine2Bookmark") private var engine2Bookmark: Data = Data()
    @AppStorage("engine2DisplayPath") private var engine2DisplayPath: String = ""
    @State private var showPathPicker = false
    @State private var pickerTarget: EngineSlot = .primary
    @State private var bookmarkError: String? = nil
    @State private var engine2PickError: String? = nil

    @State private var mode: ControlsMode = .analysis
    @State private var orientation: PieceColor = .white
    @State private var depth: Double = 16
    @State private var multipv: Double = 3
    @State private var skill: Double = 12
    @State private var movetimeMs: Double = 800
    @State private var playerColor: PieceColor = .white
    @State private var match = MatchSettings()
    @State private var matchRunning = false
    @State private var matchNotice: String? = nil

    @State private var searchTask: Task<Void, Never>? = nil
    @State private var launchTask: Task<Void, Never>? = nil
    @State private var engine2LaunchTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if stockfishBookmark.isEmpty || isEngineError {
                pathPrompt
            } else {
                HStack(alignment: .top, spacing: 24) {
                    HStack(alignment: .top, spacing: 14) {
                        // The eval bar is analysis kit: showing it while you
                        // play would hand you the verdict on every move.
                        if mode != .play {
                            EvalBarView(score: panelEngine.lines.first?.score, orientation: orientation)
                        }
                        BoardView(
                            game: game,
                            orientation: orientation,
                            arrow: engineArrow,
                            interactive: interactive,
                            onMove: { from, to in game.makeMove(from: from, to: to) }
                        )
                    }
                    .frame(maxWidth: 600)

                    VStack(spacing: 14) {
                        AnalysisPanelView(
                            engine: panelEngine,
                            fen: mode == .match ? matchPanel.fen : game.fen,
                            title: panelTitle,
                            onPlayLine: mode == .analysis && game.atLatest ? { game.applyUCI($0) } : nil,
                            playStatusText: playStatusText
                        )
                        MoveListView(game: game)
                        ControlsView(
                            mode: $mode, depth: $depth, multipv: $multipv, skill: $skill,
                            movetimeMs: $movetimeMs, playerColor: $playerColor,
                            onNewGame: newGame,
                            onUndo: game.undo,
                            onFlip: { orientation = orientation == .white ? .black : .white },
                            onGoTo: game.goTo,
                            cursor: game.cursor,
                            lastPly: game.sanMoves.count,
                            fen: game.fen,
                            pgn: game.pgn,
                            onLoadFEN: game.loadFEN
                        ) {
                            MatchControlsView(
                                white: seat(for: .white),
                                black: seat(for: .black),
                                running: matchRunning,
                                canStart: !game.isGameOver,
                                hasMoves: !game.sanMoves.isEmpty,
                                notice: matchNotice,
                                onToggle: toggleMatch,
                                onSwap: { match.engine2PlaysWhite.toggle() }
                            )
                        }
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
        .onDisappear {
            engine.shutdown()
            engine2.shutdown()
        }
        .onChange(of: game.fen) { _ in scheduleSearch() }
        .onChange(of: mode) { newValue in
            if newValue == .match {
                launchEngine2IfNeeded()
            } else {
                matchRunning = false
            }
            scheduleSearch()
        }
        .onChange(of: matchRunning) { _ in scheduleSearch() }
        .onChange(of: match.engine2PlaysWhite) { _ in scheduleSearch() }
        .onChange(of: depth) { _ in scheduleSearch() }
        .onChange(of: multipv) { _ in scheduleSearch() }
        .onChange(of: playerColor) { newValue in
            // Turn the board to face whoever you've chosen to play, so your
            // own pieces are the ones nearest to hand. "Flip board" still
            // works afterwards if you want to look from the other side.
            orientation = newValue
            scheduleSearch()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Analysis Desk")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                if !stockfishBookmark.isEmpty {
                    Button("Change engine…") { chooseEngine(.primary) }
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
            onCompletion: handlePick
        )
    }

    private func chooseEngine(_ slot: EngineSlot) {
        pickerTarget = slot
        showPathPicker = true
    }

    private func handlePick(_ result: Result<URL, Error>) {
        let slot = pickerTarget
        func fail(_ error: Error, _ stage: String) {
            let nsError = error as NSError
            print("[engine-pick] \(stage) failed: domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")
            let message = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
            switch slot {
            case .primary: bookmarkError = message
            case .second: engine2PickError = message
            }
        }

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
                switch slot {
                case .primary:
                    stockfishBookmark = bookmark
                    stockfishDisplayPath = url.path
                    bookmarkError = nil
                    launchEngineIfNeeded(force: true)
                    // The second engine borrows this binary until it's given one of its own.
                    if engine2Bookmark.isEmpty, engine2.status != .idle {
                        launchEngine2IfNeeded(force: true)
                    }
                case .second:
                    engine2Bookmark = bookmark
                    engine2DisplayPath = url.path
                    engine2PickError = nil
                    launchEngine2IfNeeded(force: true)
                }
            } catch {
                fail(error, "bookmarkData")
            }
        case .failure(let error):
            fail(error, "fileImporter")
        }
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
            Button("Choose Stockfish binary…") { chooseEngine(.primary) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brass)
        }
    }

    private var interactive: Bool {
        !game.isGameOver && game.atLatest && (mode == .analysis || (mode == .play && game.turn == playerColor))
    }

    /// Non-nil only while playing a game, which is also what tells the panel
    /// to keep the evaluation to itself.
    private var playStatusText: String? {
        guard mode == .play else { return nil }
        if let result = game.result { return result }
        if !game.atLatest { return "Reviewing an earlier move." }
        return game.turn == playerColor ? "Your move." : "Stockfish is thinking…"
    }

    /// The engine's current top choice: always in analysis, and in a match
    /// only while the side to move is still thinking about it.
    private var engineArrow: (from: Int, to: Int)? {
        let line: EngineManager.EngineLine?
        switch mode {
        case .analysis: line = engine.lines.first
        case .match: line = panelEngine.thinking ? panelEngine.lines.first : nil
        case .play: line = nil
        }
        guard let first = line?.pv.first,
              first.count >= 4,
              let from = Square.fromAlgebraic(String(first.prefix(2))),
              let to = Square.fromAlgebraic(String(first.dropFirst(2).prefix(2)))
        else { return nil }
        return (from, to)
    }

    // MARK: - Engine match

    private func isEngine2(_ color: PieceColor) -> Bool {
        (color == .white) == match.engine2PlaysWhite
    }

    private func matchEngine(for color: PieceColor) -> EngineManager {
        isEngine2(color) ? engine2 : engine
    }

    /// Which engine the panel and eval bar follow during a match: the side to
    /// move once it's thinking, otherwise the side that just moved — whose
    /// lines were computed on the position before the last move.
    private var matchPanel: (engine: EngineManager, fen: String, color: PieceColor) {
        let toMove = game.turn
        let mover = matchEngine(for: toMove)
        if mover.thinking || game.cursor == 0 {
            return (mover, game.fen, toMove)
        }
        return (matchEngine(for: toMove.opposite), game.positions[game.cursor - 1].toFEN(), toMove.opposite)
    }

    private var panelEngine: EngineManager {
        mode == .match ? matchPanel.engine : engine
    }

    private var panelTitle: String {
        guard mode == .match else { return "ENGINE" }
        let panel = matchPanel
        let name = isEngine2(panel.color) ? engine2Name : engine1Name
        return "\(panel.color == .white ? "WHITE" : "BLACK") · \(name.uppercased())"
    }

    private var engine1Name: String {
        engine.name ?? fileName(stockfishDisplayPath) ?? "Engine 1"
    }

    private var engine2Name: String {
        engine2.name ?? fileName(engine2DisplayPath.isEmpty ? stockfishDisplayPath : engine2DisplayPath) ?? "Engine 2"
    }

    private func fileName(_ path: String) -> String? {
        path.isEmpty ? nil : (path as NSString).lastPathComponent
    }

    private func seat(for color: PieceColor) -> MatchControlsView.Seat {
        if isEngine2(color) {
            return .init(
                slot: engine2Bookmark.isEmpty ? "Engine 2 · same binary" : "Engine 2",
                name: engine2Name,
                status: engine2.status,
                skill: $match.engine2Skill,
                movetimeMs: $match.engine2MovetimeMs,
                onChoose: { chooseEngine(.second) },
                pickError: engine2PickError
            )
        }
        return .init(
            slot: "Engine 1",
            name: engine1Name,
            status: engine.status,
            skill: $match.engine1Skill,
            movetimeMs: $match.engine1MovetimeMs
        )
    }

    private func toggleMatch() {
        matchNotice = nil
        if !matchRunning {
            launchEngine2IfNeeded()
            // Resuming from an earlier move would silently branch the game.
            game.goTo(game.sanMoves.count)
        }
        matchRunning.toggle()
    }

    private func newGame() {
        matchRunning = false
        matchNotice = nil
        Task {
            await engine.newGame()
            if engine2.status == .ready { await engine2.newGame() }
            game.reset()
        }
    }

    // MARK: - Launching

    private func resolvedURL(_ bookmark: Binding<Data>) -> URL? {
        guard !bookmark.wrappedValue.isEmpty else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark.wrappedValue, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            if let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                bookmark.wrappedValue = refreshed
            }
        }
        return url
    }

    private func launchEngineIfNeeded(force: Bool = false) {
        guard let url = resolvedURL($stockfishBookmark), force || engine.status == .idle else { return }
        launchTask?.cancel()
        launchTask = Task {
            await engine.launch(url: url)
            scheduleSearch()
        }
    }

    private func launchEngine2IfNeeded(force: Bool = false) {
        let url = engine2Bookmark.isEmpty ? resolvedURL($stockfishBookmark) : resolvedURL($engine2Bookmark)
        guard let url, force || engine2.status == .idle else { return }
        engine2LaunchTask?.cancel()
        engine2LaunchTask = Task {
            await engine2.launch(url: url)
            scheduleSearch()
        }
    }

    // MARK: - Searching

    private func scheduleSearch() {
        // Cancel first: in a match the running search may belong to the
        // other engine, and it must stop even if this one isn't ready.
        searchTask?.cancel()
        searchTask = nil

        let searcher = mode == .match ? matchEngine(for: game.turn) : engine
        guard searcher.status == .ready else { return }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000) // debounce rapid clicks
            guard !Task.isCancelled else { return }

            switch mode {
            case .analysis:
                guard !game.isGameOver else { return }
                _ = await engine.analyze(.init(fen: game.fen, turn: game.turn, depthLimit: Int(depth), multipv: Int(multipv)))
            case .play:
                guard !game.isGameOver, game.atLatest, game.turn != playerColor else { return }
                let result = await engine.analyze(.init(fen: game.fen, turn: game.turn, movetime: Int(movetimeMs), multipv: 1, skillLevel: Int(skill)))
                if !Task.isCancelled, let best = result.bestmove {
                    game.applyUCI(best)
                }
            case .match:
                guard matchRunning, !game.isGameOver, game.atLatest else { return }
                let color = game.turn
                let second = isEngine2(color)
                let result = await searcher.analyze(.init(
                    fen: game.fen,
                    turn: color,
                    movetime: Int(second ? match.engine2MovetimeMs : match.engine1MovetimeMs),
                    multipv: 1,
                    skillLevel: Int(second ? match.engine2Skill : match.engine1Skill)
                ))
                guard !Task.isCancelled, let best = result.bestmove else { return }
                let before = game.sanMoves.count
                game.applyUCI(best)
                if game.sanMoves.count == before {
                    matchRunning = false
                    matchNotice = "\(second ? engine2Name : engine1Name) answered with an illegal move (\(best)), so the match is paused."
                }
            }
        }
    }
}
