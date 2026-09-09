//
//  Position.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//

import Foundation

struct CastlingRights: Equatable {
    var whiteKingSide: Bool
    var whiteQueenSide: Bool
    var blackKingSide: Bool
    var blackQueenSide: Bool
}

/// A snapshot of the game: board, side to move, castling rights, en passant
/// target, and the two FEN clocks. Value type — every move produces a new
/// one rather than mutating in place, which makes history/undo trivial.
struct Position: Equatable {
    var board: [Piece?]        // 64 squares, index via rank*8+file
    var sideToMove: PieceColor
    var castling: CastlingRights
    var enPassantSquare: Int?  // the square a capturing pawn would land on
    var halfmoveClock: Int
    var fullmoveNumber: Int

    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static var starting: Position { parseFEN(startFEN)! }

    static func parseFEN(_ fen: String) -> Position? {
        let parts = fen.split(separator: " ").map(String.init)
        guard parts.count >= 4 else { return nil }

        var board = [Piece?](repeating: nil, count: 64)
        let rankRows = parts[0].split(separator: "/")
        guard rankRows.count == 8 else { return nil }

        for (i, rowString) in rankRows.enumerated() {
            let rank = 7 - i // FEN lists rank 8 first
            var file = 0
            for ch in rowString {
                if let digit = ch.wholeNumberValue, ch.isNumber {
                    file += digit
                } else {
                    guard file <= 7, let piece = Piece(fenChar: ch) else { return nil }
                    board[rank * 8 + file] = piece
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }

        let sideToMove: PieceColor = parts[1] == "b" ? .black : .white

        var castling = CastlingRights(whiteKingSide: false, whiteQueenSide: false, blackKingSide: false, blackQueenSide: false)
        if parts[2] != "-" {
            for ch in parts[2] {
                switch ch {
                case "K": castling.whiteKingSide = true
                case "Q": castling.whiteQueenSide = true
                case "k": castling.blackKingSide = true
                case "q": castling.blackQueenSide = true
                default: break
                }
            }
        }

        let enPassant: Int? = parts[3] == "-" ? nil : Square.fromAlgebraic(parts[3])
        let halfmove = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
        let fullmove = parts.count > 5 ? (Int(parts[5]) ?? 1) : 1

        return Position(
            board: board,
            sideToMove: sideToMove,
            castling: castling,
            enPassantSquare: enPassant,
            halfmoveClock: halfmove,
            fullmoveNumber: fullmove
        )
    }

    func toFEN() -> String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row += piece.fenChar
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }

        var castleStr = ""
        if castling.whiteKingSide { castleStr += "K" }
        if castling.whiteQueenSide { castleStr += "Q" }
        if castling.blackKingSide { castleStr += "k" }
        if castling.blackQueenSide { castleStr += "q" }
        if castleStr.isEmpty { castleStr = "-" }

        let epStr = enPassantSquare.map(Square.toAlgebraic) ?? "-"

        return "\(rows.joined(separator: "/")) \(sideToMove == .white ? "w" : "b") \(castleStr) \(epStr) \(halfmoveClock) \(fullmoveNumber)"
    }
}
