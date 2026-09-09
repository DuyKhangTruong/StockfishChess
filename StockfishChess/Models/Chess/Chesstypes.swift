//
//  Chesstypes.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/23/26.
//


import Foundation

/// Named `PieceColor`, not `Color` — this file lives in the same module as
/// SwiftUI views, and a type called `Color` here would shadow `SwiftUI.Color`
/// everywhere in the app. Worth knowing if you rename things later.
enum PieceColor: String, Hashable {
    case white, black

    var opposite: PieceColor { self == .white ? .black : .white }
}

enum PieceType: String, CaseIterable, Hashable {
    case pawn, knight, bishop, rook, queen, king

    /// Letter used in SAN and algebraic move text. Pawns have none.
    var sanLetter: String {
        switch self {
        case .pawn: return ""
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    init?(sanLetter: String) {
        switch sanLetter {
        case "N": self = .knight
        case "B": self = .bishop
        case "R": self = .rook
        case "Q": self = .queen
        case "K": self = .king
        default: return nil
        }
    }
}

struct Piece: Hashable {
    var type: PieceType
    var color: PieceColor

    init(type: PieceType, color: PieceColor) {
        self.type = type
        self.color = color
    }

    /// Parses a single FEN board character, e.g. "P" (white pawn), "n" (black knight).
    init?(fenChar ch: Character) {
        let isWhite = ch.isUppercase
        switch Character(ch.lowercased()) {
        case "p": type = .pawn
        case "n": type = .knight
        case "b": type = .bishop
        case "r": type = .rook
        case "q": type = .queen
        case "k": type = .king
        default: return nil
        }
        self.color = isWhite ? .white : .black
    }

    var fenChar: String {
        let letter: String
        switch type {
        case .pawn: letter = "p"
        case .knight: letter = "n"
        case .bishop: letter = "b"
        case .rook: letter = "r"
        case .queen: letter = "q"
        case .king: letter = "k"
        }
        return color == .white ? letter.uppercased() : letter
    }

    /// Unicode chess glyph. Colour is applied separately via foregroundStyle,
    /// so both sides share the same glyph set here.
    var glyph: String {
        switch type {
        case .pawn: return "♟"
        case .knight: return "♞"
        case .bishop: return "♝"
        case .rook: return "♜"
        case .queen: return "♛"
        case .king: return "♚"
        }
    }
}

/// Squares are indices 0...63, a1 = 0, h1 = 7, a8 = 56, h8 = 63 —
/// i.e. `rank * 8 + file`, matching how most chess engines think.
enum Square {
    static func file(_ sq: Int) -> Int { sq % 8 }
    static func rank(_ sq: Int) -> Int { sq / 8 }

    static func fileChar(_ sq: Int) -> Character {
        Character(UnicodeScalar(UInt8(97 + file(sq))))
    }

    static func rankChar(_ sq: Int) -> Character {
        Character("\(rank(sq) + 1)")
    }

    static func fromAlgebraic(_ s: String) -> Int? {
        let chars = Array(s.lowercased())
        guard chars.count == 2,
              let fileAscii = chars[0].asciiValue,
              (97...104).contains(fileAscii),
              let rankDigit = chars[1].wholeNumberValue,
              (1...8).contains(rankDigit)
        else { return nil }
        let file = Int(fileAscii) - 97
        let rank = rankDigit - 1
        return rank * 8 + file
    }

    static func toAlgebraic(_ sq: Int) -> String {
        "\(fileChar(sq))\(rank(sq) + 1)"
    }
}
