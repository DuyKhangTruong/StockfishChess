//
//  EvalBarView.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//
import SwiftUI

struct EvalBarView: View {
    var score: Score?
    var orientation: PieceColor = .white

    private var whiteShare: Double {
        let raw = UCI.whiteShare(score)
        return orientation == .white ? raw : 1 - raw
    }
    private var favorsWhite: Bool { whiteShare >= 0.5 }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.ink.opacity(0.6))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [Theme.bone, Color(hex: "cfc6b2")], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(0, geo.size.height * whiteShare))
                }
                .overlay(
                    Rectangle()
                        .fill(Theme.brass.opacity(0.7))
                        .frame(height: 1)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                )
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line, lineWidth: 1))
                .animation(.easeOut(duration: 0.25), value: whiteShare)
            }
            Text(UCI.format(score))
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(favorsWhite ? Theme.bone : Theme.boneDim)
        }
        .frame(width: 40)
    }
}
