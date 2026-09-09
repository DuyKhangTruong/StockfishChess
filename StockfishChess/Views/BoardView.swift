//
//  BoardView.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//
import SwiftUI

struct BoardView: View {
    @ObservedObject var game: ChessGame
    var orientation: PieceColor = .white
    var arrow: (from: Int, to: Int)? = nil
    var interactive: Bool = true
    var onMove: (Int, Int) -> Void

    @State private var selected: Int? = nil

    /// Squares in the order they should render, top-left first.
    private var displayedSquares: [Int] {
        (0..<64).map { i -> Int in
            let row = i / 8, col = i % 8
            if orientation == .white {
                return (7 - row) * 8 + col
            } else {
                return row * 8 + (7 - col)
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size / 8

            ZStack {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 0), count: 8), spacing: 0) {
                    ForEach(displayedSquares, id: \.self) { square in
                        squareView(square, size: cell)
                    }
                }
                .frame(width: size, height: size)

                if let arrow, let path = arrowPath(from: arrow.from, to: arrow.to, cell: cell) {
                    path.stroke(Theme.brass.opacity(0.85), style: StrokeStyle(lineWidth: cell * 0.09, lineCap: .round))
                        .frame(width: size, height: size)
                }

                if let pending = game.pendingPromotion {
                    promotionOverlay(pending, cell: cell)
                }
            }
            .frame(width: size, height: size)
            .background(Theme.ink)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: game.cursor) { _ in selected = nil }
    }

    @ViewBuilder
    private func squareView(_ square: Int, size: CGFloat) -> some View {
        let file = Square.file(square), rank = Square.rank(square)
        let dark = (file + rank) % 2 == 0
        let piece = game.board[square]
        let isSelected = selected == square
        let isLast = game.lastMove.map { $0.from == square || $0.to == square } ?? false
        let isCheck = game.checkedKingSquare == square
        let targets = selected.map { game.legalTargets(from: $0) } ?? []
        let isTarget = targets.contains(square)

        ZStack {
            dark ? Theme.sqDark : Theme.sqLight

            if isLast { Theme.brass.opacity(0.22) }
            if isCheck {
                RadialGradient(colors: [Theme.rust.opacity(0.75), .clear], center: .center, startRadius: 0, endRadius: size * 0.6)
            }
            if isSelected {
                Rectangle().stroke(Theme.brass, lineWidth: 3)
            }
            if let piece {
                Text(piece.glyph)
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(piece.color == .white ? Color(hex: "f6f1e6") : Color(hex: "16222a"))
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            if isTarget {
                if piece != nil {
                    Circle().stroke(Color.black.opacity(0.35), lineWidth: size * 0.06).padding(size * 0.08)
                } else {
                    Circle().fill(Color.black.opacity(0.35)).frame(width: size * 0.26, height: size * 0.26)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { handleTap(square) }
    }

    private func handleTap(_ square: Int) {
        guard interactive else { return }
        if let sel = selected {
            if sel == square { selected = nil; return }
            if game.legalTargets(from: sel).contains(square) {
                onMove(sel, square)
                selected = nil
                return
            }
        }
        if let piece = game.board[square], piece.color == game.turn {
            selected = square
        } else {
            selected = nil
        }
    }

    private func arrowPath(from: Int, to: Int, cell: CGFloat) -> Path? {
        func point(for square: Int) -> CGPoint {
            let file = Square.file(square), rank = Square.rank(square)
            let (col, row): (Int, Int) = orientation == .white ? (file, 7 - rank) : (7 - file, rank)
            return CGPoint(x: CGFloat(col) * cell + cell / 2, y: CGFloat(row) * cell + cell / 2)
        }
        var path = Path()
        path.move(to: point(for: from))
        path.addLine(to: point(for: to))
        return path
    }

    @ViewBuilder
    private func promotionOverlay(_ pending: (from: Int, to: Int), cell: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.75)
            VStack(spacing: 12) {
                Text("PROMOTE TO")
                    .font(Theme.mono(11))
                    .tracking(2)
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    ForEach([PieceType.queen, .rook, .bishop, .knight], id: \.self) { type in
                        Button {
                            game.completePromotion(type)
                        } label: {
                            Text(Piece(type: type, color: game.turn).glyph)
                                .font(.system(size: cell * 0.6))
                                .frame(width: cell * 0.9, height: cell * 0.9)
                                .background(Theme.sqLight)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Cancel") { game.cancelPromotion() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
            .background(Theme.panel)
            .cornerRadius(4)
        }
    }
}
