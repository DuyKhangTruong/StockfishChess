//
//  AnalysisView.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//
import SwiftUI

struct AnalysisPanelView: View {
    @ObservedObject var engine: EngineManager
    var fen: String
    var onPlayLine: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ENGINE").font(Theme.mono(11)).tracking(2).foregroundStyle(Theme.boneDim)
                Spacer()
                Circle().fill(dotColor).frame(width: 7, height: 7)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                telemetryRow("depth", engine.depth > 0 ? "\(engine.depth)" : "—")
                telemetryRow("speed", formattedNPS)
                telemetryRow("nodes", engine.nodes > 0 ? "\(engine.nodes)" : "—")
                telemetryRow("time", engine.timeMs > 0 ? String(format: "%.1fs", Double(engine.timeMs) / 1000) : "—")
            }

            statusBody
        }
        .padding(14)
        .background(Theme.panelBackground())
    }

    @ViewBuilder
    private var statusBody: some View {
        switch engine.status {
        case .launching:
            Text("Starting the engine…").font(.system(size: 12)).foregroundStyle(Theme.muted)
        case .error(let message):
            Text("The engine didn't start: \(message)").font(.system(size: 12)).foregroundStyle(Theme.rust)
        case .idle:
            EmptyView()
        case .ready:
            if engine.lines.isEmpty {
                Text("Waiting for a position.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(engine.lines) { line in
                        Button {
                            if let first = line.pv.first { onPlayLine?(first) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(UCI.format(line.score))
                                    .font(Theme.mono(13, weight: .semibold))
                                    .foregroundStyle((line.score?.value ?? 0) >= 0 ? Theme.bone : Theme.boneDim)
                                    .frame(width: 56, alignment: .leading)
                                Text(pvString(line.pv))
                                    .font(Theme.mono(12))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dotColor: Color {
        switch engine.status {
        case .ready: return engine.thinking ? Theme.brass : Color(hex: "9a7530")
        case .error: return Theme.rust
        default: return Theme.muted
        }
    }

    private var formattedNPS: String {
        if engine.nps <= 0 { return "—" }
        if engine.nps > 1_000_000 { return String(format: "%.1fM n/s", Double(engine.nps) / 1_000_000) }
        return "\(engine.nps / 1000)k n/s"
    }

    @ViewBuilder
    private func telemetryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.mono(10)).tracking(1).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(Theme.mono(12)).foregroundStyle(Theme.bone)
        }
    }

    /// Replays a UCI variation on a scratch position so it can render in SAN
    /// instead of raw coordinates — same trick as the web version's pvToSan.
    private func pvString(_ pv: [String]) -> String {
        guard var position = Position.parseFEN(fen) else { return pv.joined(separator: " ") }
        var parts: [String] = []
        var first = true

        for uci in pv.prefix(10) {
            guard uci.count >= 4,
                  let from = Square.fromAlgebraic(String(uci.prefix(2))),
                  let to = Square.fromAlgebraic(String(uci.dropFirst(2).prefix(2)))
            else { break }
            let promotion: PieceType? = uci.count >= 5 ? PieceType(sanLetter: String(uci.suffix(1)).uppercased()) : nil
            guard let move = MoveGenerator.legalMoves(from: from, for: position)
                .first(where: { $0.to == to && $0.promotion == promotion })
            else { break }

            let number = position.fullmoveNumber
            let san = SAN.string(for: move, before: position)
            if move.movingPiece.color == .white {
                parts.append("\(number).\(san)")
            } else if first {
                parts.append("\(number)…\(san)")
            } else {
                parts.append(san)
            }
            first = false
            position = MoveGenerator.makeMove(move, on: position)
        }
        return parts.joined(separator: " ")
    }
}
