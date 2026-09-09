//
//  UCI.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//
import Foundation

struct Score: Equatable {
    enum Kind { case centipawns, mate }
    var kind: Kind
    var value: Int
}

struct EngineInfo {
    var multipv: Int = 1
    var depth: Int? = nil
    var seldepth: Int? = nil
    var nodes: Int? = nil
    var nps: Int? = nil
    var time: Int? = nil
    var score: Score? = nil
    var pv: [String] = []
}

enum UCI {
    /// Parses a line like:
    /// "info depth 18 multipv 1 score cp 34 nodes 1204331 nps 1500412 time 803 pv e2e4 e7e5"
    static func parseInfoLine(_ line: String) -> EngineInfo? {
        guard line.hasPrefix("info ") else { return nil }
        if line.contains("lowerbound") || line.contains("upperbound") { return nil }

        let tokens = line.split(separator: " ").map(String.init)
        var info = EngineInfo()
        var i = 1
        while i < tokens.count {
            switch tokens[i] {
            case "depth": i += 1; if i < tokens.count { info.depth = Int(tokens[i]) }
            case "seldepth": i += 1; if i < tokens.count { info.seldepth = Int(tokens[i]) }
            case "multipv": i += 1; if i < tokens.count { info.multipv = Int(tokens[i]) ?? 1 }
            case "nodes": i += 1; if i < tokens.count { info.nodes = Int(tokens[i]) }
            case "nps": i += 1; if i < tokens.count { info.nps = Int(tokens[i]) }
            case "time": i += 1; if i < tokens.count { info.time = Int(tokens[i]) }
            case "score":
                i += 1
                guard i < tokens.count else { break }
                let kind: Score.Kind = tokens[i] == "mate" ? .mate : .centipawns
                i += 1
                guard i < tokens.count, let value = Int(tokens[i]) else { break }
                info.score = Score(kind: kind, value: value)
            case "pv":
                info.pv = Array(tokens[(i + 1)...])
                i = tokens.count
                continue
            default:
                break
            }
            i += 1
        }

        guard info.score != nil, !info.pv.isEmpty else { return nil }
        return info
    }

    /// UCI reports scores from the side to move. The UI always shows
    /// evaluation from White's perspective, so flip when Black is to move.
    static func normalize(_ score: Score?, turn: PieceColor) -> Score? {
        guard let score else { return nil }
        let sign = turn == .white ? 1 : -1
        return Score(kind: score.kind, value: score.value * sign)
    }

    /// "+0.34", "−1.28", "M4", "−M2"
    static func format(_ score: Score?) -> String {
        guard let score else { return "—" }
        if score.kind == .mate {
            if score.value == 0 { return "#" }
            return "\(score.value > 0 ? "" : "−")M\(abs(score.value))"
        }
        let pawns = Double(score.value) / 100
        let sign = pawns > 0 ? "+" : (pawns < 0 ? "−" : "")
        return "\(sign)\(String(format: "%.2f", abs(pawns)))"
    }

    /// Maps a score onto 0...1, 1 = winning for White. Used for the eval bar.
    static func whiteShare(_ score: Score?) -> Double {
        guard let score else { return 0.5 }
        if score.kind == .mate { return score.value > 0 ? 1 : 0 }
        let capped = max(-1500, min(1500, Double(score.value)))
        return 1 / (1 + exp(-capped / 350))
    }
}
