//
//  ChessGame.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//
import Foundation
import Combine

/// The authoritative game state. Both `BoardView` and `EngineManager` read
/// the position from here; they never talk to each other directly.
@MainActor
final class ChessGame: ObservableObject {
    @Published private(set) var positions: [Position]
    @Published private(set) var sanMoves: [String] = []
    @Published private(set) var movesPlayed: [Move] = []
    @Published private(set) var cursor: Int = 0
    @Published var pendingPromotion: (from: Int, to: Int)? = nil

    private var repetitionCounts: [String: Int] = [:]

    init(fen: String = Position.startFEN) {
        positions = [Position.parseFEN(fen) ?? Position.starting]
        recomputeRepetition()
    }

    var position: Position { positions[cursor] }
    var board: [Piece?] { position.board }
    var turn: PieceColor { position.sideToMove }
    var fen: String { position.toFEN() }
    var atLatest: Bool { cursor == positions.count - 1 }
    var lastMove: Move? { cursor > 0 ? movesPlayed[cursor - 1] : nil }

    var inCheck: Bool { MoveGenerator.isInCheck(position) }
    var checkedKingSquare: Int? { inCheck ? MoveGenerator.kingSquare(turn, position) : nil }

    var isCheckmate: Bool { MoveGenerator.isCheckmate(position) }
    var isStalemate: Bool { MoveGenerator.isStalemate(position) }
    var isThreefold: Bool { (repetitionCounts[repetitionKey(position)] ?? 0) >= 3 }
    var isInsufficientMaterial: Bool { MoveGenerator.isInsufficientMaterial(position) }
    var isFiftyMoveDraw: Bool { position.halfmoveClock >= 100 }
    var isGameOver: Bool { isCheckmate || isStalemate || isThreefold || isInsufficientMaterial || isFiftyMoveDraw }

    var result: String? {
        guard isGameOver else { return nil }
        if isCheckmate { return turn == .white ? "Black wins by checkmate" : "White wins by checkmate" }
        if isStalemate { return "Draw by stalemate" }
        if isThreefold { return "Draw by repetition" }
        if isInsufficientMaterial { return "Draw — insufficient material" }
        return "Draw by the fifty-move rule"
    }

    func legalTargets(from square: Int) -> [Int] {
        MoveGenerator.legalMoves(from: square, for: position).map { $0.to }
    }

    /// Attempts a move. If it needs a promotion choice, sets `pendingPromotion`
    /// and returns true without committing — call `completePromotion` next.
    @discardableResult
    func makeMove(from: Int, to: Int) -> Bool {
        let candidates = MoveGenerator.legalMoves(from: from, for: position).filter { $0.to == to }
        guard !candidates.isEmpty else { return false }
        if candidates[0].promotion != nil {
            pendingPromotion = (from, to)
            return true
        }
        commit(candidates[0])
        return true
    }

    func completePromotion(_ type: PieceType) {
        guard let pending = pendingPromotion,
              let move = MoveGenerator.legalMoves(from: pending.from, for: position)
                .first(where: { $0.to == pending.to && $0.promotion == type })
        else {
            pendingPromotion = nil
            return
        }
        commit(move)
        pendingPromotion = nil
    }

    func cancelPromotion() { pendingPromotion = nil }

    /// Plays a move written in UCI coordinate form, e.g. "e2e4" or "e7e8q".
    func applyUCI(_ uci: String) {
        guard uci.count >= 4,
              let from = Square.fromAlgebraic(String(uci.prefix(2))),
              let to = Square.fromAlgebraic(String(uci.dropFirst(2).prefix(2)))
        else { return }
        let promotion: PieceType? = uci.count >= 5 ? PieceType(sanLetter: String(uci.suffix(1)).uppercased()) : nil
        guard let move = MoveGenerator.legalMoves(from: from, for: position)
            .first(where: { $0.to == to && $0.promotion == promotion })
        else { return }
        commit(move)
    }

    private func commit(_ move: Move) {
        let san = SAN.string(for: move, before: position)
        let newPosition = MoveGenerator.makeMove(move, on: position)
        positions = Array(positions.prefix(cursor + 1)) + [newPosition]
        movesPlayed = Array(movesPlayed.prefix(cursor)) + [move]
        sanMoves = Array(sanMoves.prefix(cursor)) + [san]
        cursor += 1
        recomputeRepetition()
    }

    func goTo(_ index: Int) {
        cursor = max(0, min(index, positions.count - 1))
    }

    func undo() {
        guard positions.count > 1 else { return }
        positions.removeLast()
        movesPlayed.removeLast()
        sanMoves.removeLast()
        cursor = min(cursor, positions.count - 1)
        recomputeRepetition()
    }

    func reset(fen: String = Position.startFEN) {
        positions = [Position.parseFEN(fen) ?? Position.starting]
        movesPlayed = []
        sanMoves = []
        cursor = 0
        pendingPromotion = nil
        recomputeRepetition()
    }

    @discardableResult
    func loadFEN(_ fen: String) -> Bool {
        guard let pos = Position.parseFEN(fen) else { return false }
        positions = [pos]
        movesPlayed = []
        sanMoves = []
        cursor = 0
        pendingPromotion = nil
        recomputeRepetition()
        return true
    }

    var pgn: String {
        var s = ""
        for (i, san) in sanMoves.enumerated() {
            if i % 2 == 0 { s += "\(i / 2 + 1). " }
            s += san + " "
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// FEN with the move counters zeroed out, so identical positions with
    /// different clocks still count as the same position for repetition.
    private func repetitionKey(_ p: Position) -> String {
        var copy = p
        copy.halfmoveClock = 0
        copy.fullmoveNumber = 1
        return copy.toFEN()
    }

    private func recomputeRepetition() {
        repetitionCounts = [:]
        for p in positions {
            repetitionCounts[repetitionKey(p), default: 0] += 1
        }
    }
}
