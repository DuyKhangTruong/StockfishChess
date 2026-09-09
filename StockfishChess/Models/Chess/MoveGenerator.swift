//
//  MoveGenerator.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//
import Foundation

struct Move: Equatable {
    var from: Int
    var to: Int
    var movingPiece: Piece
    var capturedPiece: Piece?
    var promotion: PieceType?
    var isCastleKingSide: Bool
    var isCastleQueenSide: Bool
    var isEnPassant: Bool
    var isDoublePawnPush: Bool

    /// Custom init, deliberately — Swift requires call-site arguments to
    /// follow declaration order even with labels, and this type is built in
    /// a lot of places. One fixed order here beats re-deriving it each time.
    init(
        from: Int,
        to: Int,
        movingPiece: Piece,
        capturedPiece: Piece? = nil,
        promotion: PieceType? = nil,
        isCastleKingSide: Bool = false,
        isCastleQueenSide: Bool = false,
        isEnPassant: Bool = false,
        isDoublePawnPush: Bool = false
    ) {
        self.from = from
        self.to = to
        self.movingPiece = movingPiece
        self.capturedPiece = capturedPiece
        self.promotion = promotion
        self.isCastleKingSide = isCastleKingSide
        self.isCastleQueenSide = isCastleQueenSide
        self.isEnPassant = isEnPassant
        self.isDoublePawnPush = isDoublePawnPush
    }
}

/// Pure move generation and application. Every function here is a static
/// function of a `Position` — nothing is mutated in place, so simulating a
/// move to test for check is just "call makeMove and look at the result".
enum MoveGenerator {
    static let diagonalDirections: [(Int, Int)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    static let orthogonalDirections: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    // MARK: - Attacks

    static func knightOffsets(from square: Int) -> [Int] {
        let f = Square.file(square), r = Square.rank(square)
        let deltas = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
        return deltas.compactMap { (df, dr) in
            let nf = f + df, nr = r + dr
            guard (0...7).contains(nf), (0...7).contains(nr) else { return nil }
            return nr * 8 + nf
        }
    }

    static func kingOffsets(from square: Int) -> [Int] {
        let f = Square.file(square), r = Square.rank(square)
        let deltas = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        return deltas.compactMap { (df, dr) in
            let nf = f + df, nr = r + dr
            guard (0...7).contains(nf), (0...7).contains(nr) else { return nil }
            return nr * 8 + nf
        }
    }

    private static func pawnAttackerSquares(of square: Int, attackerColor: PieceColor) -> [Int] {
        let f = Square.file(square), r = Square.rank(square)
        let attackerRank = r + (attackerColor == .white ? -1 : 1)
        guard (0...7).contains(attackerRank) else { return [] }
        return [-1, 1].compactMap { df in
            let af = f + df
            guard (0...7).contains(af) else { return nil }
            return attackerRank * 8 + af
        }
    }

    private static func firstOccupiedSquare(from square: Int, direction: (Int, Int), board: [Piece?]) -> Int? {
        var f = Square.file(square), r = Square.rank(square)
        while true {
            f += direction.0; r += direction.1
            guard (0...7).contains(f), (0...7).contains(r) else { return nil }
            let sq = r * 8 + f
            if board[sq] != nil { return sq }
        }
    }

    static func isAttacked(_ square: Int, by color: PieceColor, on position: Position) -> Bool {
        let board = position.board

        for sq in pawnAttackerSquares(of: square, attackerColor: color) {
            if let p = board[sq], p.color == color, p.type == .pawn { return true }
        }
        for sq in knightOffsets(from: square) {
            if let p = board[sq], p.color == color, p.type == .knight { return true }
        }
        for sq in kingOffsets(from: square) {
            if let p = board[sq], p.color == color, p.type == .king { return true }
        }
        for dir in diagonalDirections {
            if let sq = firstOccupiedSquare(from: square, direction: dir, board: board),
               let p = board[sq], p.color == color, p.type == .bishop || p.type == .queen {
                return true
            }
        }
        for dir in orthogonalDirections {
            if let sq = firstOccupiedSquare(from: square, direction: dir, board: board),
               let p = board[sq], p.color == color, p.type == .rook || p.type == .queen {
                return true
            }
        }
        return false
    }

    static func kingSquare(_ color: PieceColor, _ position: Position) -> Int? {
        for i in 0..<64 {
            if let p = position.board[i], p.type == .king, p.color == color { return i }
        }
        return nil
    }

    static func isInCheck(_ position: Position) -> Bool {
        guard let king = kingSquare(position.sideToMove, position) else { return false }
        return isAttacked(king, by: position.sideToMove.opposite, on: position)
    }

    // MARK: - Pseudo-legal generation per piece

    private static func addPawnMove(from: Int, to: Int, promotionRank: Int, color: PieceColor, into moves: inout [Move], capturedPiece: Piece? = nil) {
        let piece = Piece(type: .pawn, color: color)
        if Square.rank(to) == promotionRank {
            for promo in [PieceType.queen, .rook, .bishop, .knight] {
                moves.append(Move(from: from, to: to, movingPiece: piece, capturedPiece: capturedPiece, promotion: promo))
            }
        } else {
            moves.append(Move(from: from, to: to, movingPiece: piece, capturedPiece: capturedPiece))
        }
    }

    private static func pawnMoves(from square: Int, position: Position) -> [Move] {
        guard let piece = position.board[square], piece.type == .pawn else { return [] }
        var moves: [Move] = []
        let color = piece.color
        let dir = color == .white ? 1 : -1
        let startRank = color == .white ? 1 : 6
        let promotionRank = color == .white ? 7 : 0
        let f = Square.file(square), r = Square.rank(square)

        let oneRank = r + dir
        if (0...7).contains(oneRank) {
            let oneSq = oneRank * 8 + f
            if position.board[oneSq] == nil {
                addPawnMove(from: square, to: oneSq, promotionRank: promotionRank, color: color, into: &moves)
                if r == startRank {
                    let twoSq = (r + 2 * dir) * 8 + f
                    if position.board[twoSq] == nil {
                        moves.append(Move(from: square, to: twoSq, movingPiece: piece, isDoublePawnPush: true))
                    }
                }
            }
        }

        for df in [-1, 1] {
            let cf = f + df
            guard (0...7).contains(cf) else { continue }
            let cr = r + dir
            guard (0...7).contains(cr) else { continue }
            let csq = cr * 8 + cf
            if let target = position.board[csq], target.color != color {
                addPawnMove(from: square, to: csq, promotionRank: promotionRank, color: color, into: &moves, capturedPiece: target)
            } else if csq == position.enPassantSquare {
                var m = Move(from: square, to: csq, movingPiece: piece, isEnPassant: true)
                m.capturedPiece = position.board[csq - dir * 8]
                moves.append(m)
            }
        }
        return moves
    }

    private static func knightMoves(from square: Int, position: Position) -> [Move] {
        guard let piece = position.board[square] else { return [] }
        return knightOffsets(from: square).compactMap { target in
            if let occupant = position.board[target] {
                return occupant.color != piece.color ? Move(from: square, to: target, movingPiece: piece, capturedPiece: occupant) : nil
            }
            return Move(from: square, to: target, movingPiece: piece)
        }
    }

    private static func slidingMoves(from square: Int, position: Position, directions: [(Int, Int)]) -> [Move] {
        guard let piece = position.board[square] else { return [] }
        var moves: [Move] = []
        for dir in directions {
            var f = Square.file(square), r = Square.rank(square)
            while true {
                f += dir.0; r += dir.1
                guard (0...7).contains(f), (0...7).contains(r) else { break }
                let sq = r * 8 + f
                if let occupant = position.board[sq] {
                    if occupant.color != piece.color {
                        moves.append(Move(from: square, to: sq, movingPiece: piece, capturedPiece: occupant))
                    }
                    break
                }
                moves.append(Move(from: square, to: sq, movingPiece: piece))
            }
        }
        return moves
    }

    private static func kingMoves(from square: Int, position: Position) -> [Move] {
        guard let piece = position.board[square] else { return [] }
        var moves: [Move] = kingOffsets(from: square).compactMap { target in
            if let occupant = position.board[target] {
                return occupant.color != piece.color ? Move(from: square, to: target, movingPiece: piece, capturedPiece: occupant) : nil
            }
            return Move(from: square, to: target, movingPiece: piece)
        }

        let color = piece.color
        let enemy = color.opposite
        let rank = color == .white ? 0 : 7
        let kingHome = rank * 8 + 4
        guard square == kingHome, !isAttacked(kingHome, by: enemy, on: position) else { return moves }

        let kingSideRight = color == .white ? position.castling.whiteKingSide : position.castling.blackKingSide
        if kingSideRight {
            let fSquare = rank * 8 + 5, gSquare = rank * 8 + 6
            if position.board[fSquare] == nil, position.board[gSquare] == nil,
               !isAttacked(fSquare, by: enemy, on: position), !isAttacked(gSquare, by: enemy, on: position) {
                moves.append(Move(from: square, to: gSquare, movingPiece: piece, isCastleKingSide: true))
            }
        }

        let queenSideRight = color == .white ? position.castling.whiteQueenSide : position.castling.blackQueenSide
        if queenSideRight {
            let dSquare = rank * 8 + 3, cSquare = rank * 8 + 2, bSquare = rank * 8 + 1
            if position.board[dSquare] == nil, position.board[cSquare] == nil, position.board[bSquare] == nil,
               !isAttacked(dSquare, by: enemy, on: position), !isAttacked(cSquare, by: enemy, on: position) {
                moves.append(Move(from: square, to: cSquare, movingPiece: piece, isCastleQueenSide: true))
            }
        }

        return moves
    }

    static func pseudoLegalMoves(for position: Position) -> [Move] {
        var moves: [Move] = []
        for sq in 0..<64 {
            guard let piece = position.board[sq], piece.color == position.sideToMove else { continue }
            switch piece.type {
            case .pawn: moves += pawnMoves(from: sq, position: position)
            case .knight: moves += knightMoves(from: sq, position: position)
            case .bishop: moves += slidingMoves(from: sq, position: position, directions: diagonalDirections)
            case .rook: moves += slidingMoves(from: sq, position: position, directions: orthogonalDirections)
            case .queen: moves += slidingMoves(from: sq, position: position, directions: diagonalDirections + orthogonalDirections)
            case .king: moves += kingMoves(from: sq, position: position)
            }
        }
        return moves
    }

    // MARK: - Applying a move

    static func makeMove(_ move: Move, on position: Position) -> Position {
        var board = position.board
        let piece = move.movingPiece
        var castling = position.castling
        var enPassant: Int? = nil
        var halfmove = position.halfmoveClock + 1
        if piece.type == .pawn || move.capturedPiece != nil { halfmove = 0 }

        if move.isEnPassant {
            board[move.to - (piece.color == .white ? 8 : -8)] = nil
        }

        board[move.from] = nil
        board[move.to] = move.promotion.map { Piece(type: $0, color: piece.color) } ?? piece

        if move.isCastleKingSide {
            let rank = piece.color == .white ? 0 : 7
            board[rank * 8 + 5] = board[rank * 8 + 7]
            board[rank * 8 + 7] = nil
        } else if move.isCastleQueenSide {
            let rank = piece.color == .white ? 0 : 7
            board[rank * 8 + 3] = board[rank * 8 + 0]
            board[rank * 8 + 0] = nil
        }

        if piece.type == .king {
            if piece.color == .white { castling.whiteKingSide = false; castling.whiteQueenSide = false }
            else { castling.blackKingSide = false; castling.blackQueenSide = false }
        }
        for sq in [move.from, move.to] {
            switch sq {
            case 0: castling.whiteQueenSide = false
            case 7: castling.whiteKingSide = false
            case 56: castling.blackQueenSide = false
            case 63: castling.blackKingSide = false
            default: break
            }
        }

        if move.isDoublePawnPush {
            enPassant = (move.from + move.to) / 2
        }

        let nextFullmove = piece.color == .black ? position.fullmoveNumber + 1 : position.fullmoveNumber

        return Position(
            board: board,
            sideToMove: piece.color.opposite,
            castling: castling,
            enPassantSquare: enPassant,
            halfmoveClock: halfmove,
            fullmoveNumber: nextFullmove
        )
    }

    // MARK: - Legality filter

    static func legalMoves(for position: Position) -> [Move] {
        let side = position.sideToMove
        return pseudoLegalMoves(for: position).filter { move in
            let after = makeMove(move, on: position)
            guard let king = kingSquare(side, after) else { return false }
            return !isAttacked(king, by: side.opposite, on: after)
        }
    }

    static func legalMoves(from square: Int, for position: Position) -> [Move] {
        legalMoves(for: position).filter { $0.from == square }
    }

    static func isCheckmate(_ position: Position) -> Bool {
        isInCheck(position) && legalMoves(for: position).isEmpty
    }

    static func isStalemate(_ position: Position) -> Bool {
        !isInCheck(position) && legalMoves(for: position).isEmpty
    }

    /// Simplified: covers the common cases (bare kings, king + one minor
    /// piece). Doesn't detect same-colour-bishop draws — a real edge case,
    /// rare enough to leave as a known gap.
    static func isInsufficientMaterial(_ position: Position) -> Bool {
        let nonKingPieces = position.board.compactMap { $0 }.filter { $0.type != .king }
        if nonKingPieces.isEmpty { return true }
        if nonKingPieces.count == 1, nonKingPieces[0].type == .bishop || nonKingPieces[0].type == .knight { return true }
        return false
    }
}
