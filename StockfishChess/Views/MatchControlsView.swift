//
//  MatchControlsView.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 10/10/26.
//

import SwiftUI

/// Per-engine settings for an engine-vs-engine game. Settings belong to the
/// engine rather than the colour, so swapping sides keeps each engine's
/// handicap with it.
struct MatchSettings {
    var engine1Skill: Double = 20
    var engine1MovetimeMs: Double = 1000
    var engine2Skill: Double = 20
    var engine2MovetimeMs: Double = 1000
    var engine2PlaysWhite = false
}

struct MatchControlsView: View {
    /// One engine's chair at the board, as the controls need to show it.
    struct Seat {
        var slot: String
        var name: String
        var status: EngineManager.Status
        var skill: Binding<Double>
        var movetimeMs: Binding<Double>
        /// Only the second engine is picked here; the first is the app's main
        /// engine and is changed from the header.
        var onChoose: (() -> Void)? = nil
        var pickError: String? = nil
    }

    var white: Seat
    var black: Seat
    var running: Bool
    var canStart: Bool
    var hasMoves: Bool
    var notice: String?
    var onToggle: () -> Void
    var onSwap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            seatCard(white, color: "WHITE")
            seatCard(black, color: "BLACK")

            HStack(spacing: 6) {
                Button(running ? "Pause" : (hasMoves ? "Resume" : "Start match"), action: onToggle)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brass)
                    .disabled(!running && !canStart)
                Button("Swap colours", action: onSwap)
                    .buttonStyle(.bordered)
            }

            if let notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.rust)
            }
        }
    }

    @ViewBuilder
    private func seatCard(_ seat: Seat, color: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(color).font(Theme.mono(10)).tracking(1).foregroundStyle(Theme.brass)
                Text(seat.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(seat.slot).font(Theme.mono(10)).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                if let onChoose = seat.onChoose {
                    Button("Choose…", action: onChoose)
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.brass)
                }
            }

            if let pickError = seat.pickError {
                errorText("Couldn't use that file: \(pickError)")
            } else if case .error(let message) = seat.status {
                errorText(message)
            } else if seat.status == .launching {
                Text("Starting…").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }

            HStack(spacing: 12) {
                compactSlider("Strength", value: seat.skill, range: 0...20, display: "\(Int(seat.skill.wrappedValue))/20")
                compactSlider("Time", value: seat.movetimeMs, range: 100...5000, display: "\(Int(seat.movetimeMs.wrappedValue))ms")
            }
        }
        .padding(10)
        .background(Theme.panel2.opacity(0.6))
        .cornerRadius(3)
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.rust)
            .lineLimit(3)
    }

    @ViewBuilder
    private func compactSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label.uppercased()).font(Theme.mono(9)).tracking(1).foregroundStyle(Theme.muted)
                Spacer()
                Text(display).font(Theme.mono(9)).foregroundStyle(Theme.brass)
            }
            Slider(value: value, in: range).tint(Theme.brass).controlSize(.small)
        }
    }
}
