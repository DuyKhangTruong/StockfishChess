//
//  ControlsView.swift
//  StockfishChess
//
//  Created by Duy Khang Nguyen Truong on 8/28/26.
//
import SwiftUI

enum ControlsMode { case analysis, play, match }

struct ControlsView<MatchControls: View>: View {
    typealias Mode = ControlsMode

    @Binding var mode: Mode
    @Binding var depth: Double
    @Binding var multipv: Double
    @Binding var skill: Double
    @Binding var movetimeMs: Double
    @Binding var playerColor: PieceColor

    var onNewGame: () -> Void
    var onUndo: () -> Void
    var onFlip: () -> Void
    var onGoTo: (Int) -> Void
    var cursor: Int
    var lastPly: Int
    var fen: String
    var pgn: String
    var onLoadFEN: (String) -> Bool
    /// Shown in place of the sliders while two engines play each other.
    @ViewBuilder var matchControls: () -> MatchControls

    @State private var fenDraft = ""
    @State private var fenError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $mode) {
                Text("Analyse").tag(Mode.analysis)
                Text("Play engine").tag(Mode.play)
                Text("Engine match").tag(Mode.match)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .analysis {
                sliderField(label: "Depth", value: $depth, range: 6...26, display: "\(Int(depth))")
                sliderField(label: "Lines", value: $multipv, range: 1...5, display: "\(Int(multipv))")
            } else if mode == .match {
                matchControls()
            } else {
                sliderField(label: "Engine strength", value: $skill, range: 0...20, display: "\(Int(skill))/20")
                sliderField(label: "Thinking time", value: $movetimeMs, range: 100...3000, display: "\(Int(movetimeMs))ms")
                Picker("", selection: $playerColor) {
                    Text("Play White").tag(PieceColor.white)
                    Text("Play Black").tag(PieceColor.black)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(spacing: 4) {
                navButton("backward.end.fill") { onGoTo(0) }
                navButton("chevron.left") { onGoTo(cursor - 1) }
                navButton("chevron.right") { onGoTo(cursor + 1) }
                navButton("forward.end.fill") { onGoTo(lastPly) }
            }

            HStack(spacing: 6) {
                Button("New game", action: onNewGame).buttonStyle(.bordered)
                Button("Take back", action: onUndo).buttonStyle(.bordered)
                Button("Flip board", action: onFlip).buttonStyle(.bordered)
            }

            DisclosureGroup("Position & notation") {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("Current FEN") {
                        Text(fen)
                            .font(Theme.mono(10))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    labeledField("Load a FEN") {
                        TextField("rnbqkbnr/pppppppp/…", text: $fenDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.mono(11))
                    }
                    if fenError {
                        Text("That FEN can't be read. Check the piece placement and side to move.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.rust)
                    }
                    Button("Load position") {
                        let trimmed = fenDraft.trimmingCharacters(in: .whitespaces)
                        fenError = !onLoadFEN(trimmed)
                        if !fenError { fenDraft = "" }
                    }
                    .buttonStyle(.bordered)
                    .disabled(fenDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                    labeledField("PGN") {
                        ScrollView {
                            Text(pgn)
                                .font(Theme.mono(11))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 70)
                        .padding(6)
                        .background(Theme.ink.opacity(0.4))
                        .cornerRadius(3)
                    }
                }
                .padding(.top, 10)
            }
            .tint(Theme.brass)
        }
        .padding(14)
        .background(Theme.panelBackground())
    }

    @ViewBuilder
    private func sliderField(label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label.uppercased()).font(Theme.mono(10)).tracking(1).foregroundStyle(Theme.muted)
                Spacer()
                Text(display).font(Theme.mono(10)).foregroundStyle(Theme.brass)
            }
            Slider(value: value, in: range).tint(Theme.brass)
        }
    }

    @ViewBuilder
    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(Theme.mono(10)).tracking(1).foregroundStyle(Theme.muted)
            content()
        }
    }
}
