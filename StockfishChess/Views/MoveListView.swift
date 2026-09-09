//
//  MoveListView.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//
import SwiftUI

struct MoveListView: View {
    @ObservedObject var game: ChessGame

    private struct Row: Identifiable {
        let id: Int
        let number: Int
        let white: (ply: Int, san: String)
        let black: (ply: Int, san: String)?
    }

    private var rows: [Row] {
        var result: [Row] = []
        var i = 0
        while i < game.sanMoves.count {
            let number = i / 2 + 1
            let white = (ply: i + 1, san: game.sanMoves[i])
            let black: (ply: Int, san: String)? = (i + 1 < game.sanMoves.count) ? (ply: i + 2, san: game.sanMoves[i + 1]) : nil
            result.append(Row(id: number, number: number, white: white, black: black))
            i += 2
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SCORESHEET").font(Theme.mono(11)).tracking(2).foregroundStyle(Theme.boneDim)
                Spacer()
                Text("\(game.sanMoves.count) ply").font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 8)

            if rows.isEmpty {
                Text("No moves yet. Play 1.e4 — or anything else.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                HStack(spacing: 4) {
                                    Text("\(row.number)")
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.muted)
                                        .frame(width: 24, alignment: .leading)
                                    plyButton(row.white.san, ply: row.white.ply)
                                    if let black = row.black {
                                        plyButton(black.san, ply: black.ply)
                                    } else {
                                        Text("—").font(Theme.mono(13)).foregroundStyle(Theme.line)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .id(row.number)
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: game.cursor) { newCursor in
                        withAnimation { proxy.scrollTo(max(1, (newCursor + 1) / 2), anchor: .center) }
                    }
                }
            }

            if let result = game.result {
                Text(result)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Theme.panel2)
                    .cornerRadius(3)
                    .padding(.top, 12)
            }
        }
        .padding(14)
        .background(Theme.panelBackground())
    }

    @ViewBuilder
    private func plyButton(_ san: String, ply: Int) -> some View {
        Button {
            game.goTo(ply)
        } label: {
            Text(san)
                .font(Theme.mono(13))
                .foregroundStyle(game.cursor == ply ? Theme.ink : Theme.bone)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(game.cursor == ply ? Theme.brass : Color.clear)
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}
