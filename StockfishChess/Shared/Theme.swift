//
//  Theme.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//

import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255,
            green: Double((rgb & 0x00FF00) >> 8) / 255,
            blue: Double(rgb & 0x0000FF) / 255
        )
    }
}

enum Theme {
    static let ink = Color(hex: "101a20")
    static let panel = Color(hex: "1b2b34")
    static let panel2 = Color(hex: "223640")
    static let line = Color(hex: "2c434f")
    static let bone = Color(hex: "ece4d3")
    static let boneDim = Color(hex: "a9b8bf")
    static let muted = Color(hex: "7d949e")
    static let sqLight = Color(hex: "dfd6c0")
    static let sqDark = Color(hex: "55707b")
    static let brass = Color(hex: "c99a3c")
    static let rust = Color(hex: "b4573a")

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, design: .monospaced).weight(weight)
    }

    static func panelBackground() -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(panel)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(line, lineWidth: 1))
    }
}
