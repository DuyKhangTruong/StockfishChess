//
//  SAN.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//
import Foundation

/// Renders a `Move` as standard algebraic notation ("Nf3", "exd5", "O-O+").
/// Needs `before` — the position the move was played from — to figure out
/// disambiguation and to compute the resulting check/mate suffix.
enum SAN {
    static func string(for move: Move, before position: Position) -> String {
        if move.isCastleKingSide { return withSuffix("O-O", move: move, before: position) }
        if move.isCastleQueenSide { return withSuffix("O-O-O", move: move, before: position) }

        let piece = move.movingPiece
        let isCapture = move.capturedPiece != nil || move.isEnPassant
        var s = ""

        if piece.type != .pawn {
            s += piece.type.sanLetter
            s += disambiguation(for: move, before: position)
        } else if isCapture {
            s += String(Square.fileChar(move.from))
        }

        if isCapture { s += "x" }
        s += Square.toAlgebraic(move.to)
        if let promo = move.promotion { s += "=" + promo.sanLetter }

        return withSuffix(s, move: move, before: position)
    }

    private static func withSuffix(_ base: String, move: Move, before position: Position) -> String {
        let after = MoveGenerator.makeMove(move, on: position)
        if MoveGenerator.isCheckmate(after) { return base + "#" }
        if MoveGenerator.isInCheck(after) { return base + "+" }
        return base
    }

    private static func disambiguation(for move: Move, before position: Position) -> String {
        let siblings = MoveGenerator.legalMoves(for: position).filter {
            $0.to == move.to && $0.movingPiece.type == move.movingPiece.type && $0.from != move.from
        }
        guard !siblings.isEmpty else { return "" }

        let sameFile = siblings.contains { Square.file($0.from) == Square.file(move.from) }
        let sameRank = siblings.contains { Square.rank($0.from) == Square.rank(move.from) }

        if !sameFile { return String(Square.fileChar(move.from)) }
        if !sameRank { return String(Square.rankChar(move.from)) }
        return Square.toAlgebraic(move.from)
    }
}
