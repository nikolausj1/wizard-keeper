import SwiftUI
import SwiftData

/// Screen D (iPad): the full-history scorepad grid — Mockup E, Frame 4
/// ("Screen D on iPad"). One column per seated participant, one row per
/// round, a pinned header row and a pinned running-total row bracketing a
/// vertically scrolling body. Replaces the iPhone standings list on
/// `.regular` horizontal size class; `GameView` decides which to show.
struct ScorepadGridView: View {
    @Bindable var game: Game
    @State private var navigateToRoundEntry = false

    /// Fixed width of the leading "RND" column, matching the mockup's
    /// `grid-template-columns: 56px repeat(N, 1fr)`.
    private let roundColumnWidth: CGFloat = 56
    private let outerHPadding: CGFloat = 20

    private enum RowKind {
        case completed(deltas: [Int], cumulative: [Int])
        case current
        case future
    }

    private struct RoundRow: Identifiable {
        let id: Int
        let roundNumber: Int
        let kind: RowKind
    }

    private var participants: [Participant] { game.participants }

    private var completedRoundCount: Int {
        game.orderedRounds.filter { $0.phase == .complete }.count
    }

    private var totals: [Int] {
        participants.map { game.runningTotal(for: $0.playerId) }
    }

    /// Seat indices currently tied for the lead. Empty until at least one
    /// round has been completed, so an all-zero opening board shows no star.
    private var leaderIndices: Set<Int> {
        completedRoundCount == 0 ? [] : Set(WizardEngine.winners(totals: totals))
    }

    /// One `RoundRow` per round number 1...totalRounds, built by walking
    /// completed rounds in order and accumulating each player's running
    /// total via `Round.score(for:)` — the same derivation `Game` itself
    /// uses, never hand-computed here.
    private var rows: [RoundRow] {
        let ordered = game.orderedRounds
        let current = game.currentRoundNumber
        var running = [Int](repeating: 0, count: participants.count)
        var result: [RoundRow] = []

        for n in 1...max(game.totalRounds, 1) {
            if let round = ordered.first(where: { $0.roundNumber == n }), round.phase == .complete {
                var deltas: [Int] = []
                deltas.reserveCapacity(participants.count)
                for (i, participant) in participants.enumerated() {
                    let delta = round.score(for: participant.playerId) ?? 0
                    deltas.append(delta)
                    running[i] += delta
                }
                result.append(RoundRow(id: n, roundNumber: n, kind: .completed(deltas: deltas, cumulative: running)))
            } else if n == current {
                result.append(RoundRow(id: n, roundNumber: n, kind: .current))
            } else {
                result.append(RoundRow(id: n, roundNumber: n, kind: .future))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: nil, title: "Scorepad", subtitle: subtitleText, titleSize: 28)
                .padding(.horizontal, outerHPadding)

            headerRow
                .padding(.horizontal, outerHPadding)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(.separator)).frame(height: 1)
                }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                .padding(.horizontal, outerHPadding)
            }

            totalRow
                .padding(.horizontal, outerHPadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(.separator)).frame(height: 1)
                }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            if game.status != .completed {
                bottomBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToRoundEntry) {
            RoundEntryView(game: game, roundNumber: game.currentRoundNumber)
        }
    }

    private var subtitleText: String {
        let n = game.currentRoundNumber
        return "Round \(n) of \(game.totalRounds) · deal \(n) card\(n == 1 ? "" : "s") each"
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("RND")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: roundColumnWidth, alignment: .leading)

            ForEach(Array(participants.enumerated()), id: \.offset) { index, participant in
                HStack(spacing: 4) {
                    Text(participant.displayNameSnapshot)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if leaderIndices.contains(index) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Body rows

    @ViewBuilder
    private func rowView(_ row: RoundRow) -> some View {
        switch row.kind {
        case .completed(let deltas, let cumulative):
            completedRow(roundNumber: row.roundNumber, deltas: deltas, cumulative: cumulative)
        case .current:
            currentRow(roundNumber: row.roundNumber)
        case .future:
            futureRow(roundNumber: row.roundNumber)
        }
    }

    /// Shared row scaffold: fixed round-number column + flexible per-player
    /// columns, with the tint/corner-radius treatment `.current` needs and
    /// a hairline separator every row carries, matching `.gridrow` /
    /// `.gridrow.current` in the mockup.
    @ViewBuilder
    private func rowShell<Content: View>(
        roundNumber: Int,
        tinted: Bool,
        numberColor: Color,
        @ViewBuilder cells: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            Text("\(roundNumber)")
                .font(.system(size: 12.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .frame(width: roundColumnWidth, alignment: .leading)
            cells()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(tinted ? Color.indigo.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: tinted ? 8 : 0, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.separator).opacity(0.5)).frame(height: 0.5)
        }
    }

    private func completedRow(roundNumber: Int, deltas: [Int], cumulative: [Int]) -> some View {
        rowShell(roundNumber: roundNumber, tinted: false, numberColor: .secondary) {
            ForEach(participants.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 1) {
                    Text(ScoreFormat.delta(deltas[i]))
                        .font(.system(size: 13.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(deltas[i] >= 0 ? .green : .red)
                    Text(ScoreFormat.score(cumulative[i]))
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The in-progress round: indigo tint, "—" placeholders, and the whole
    /// row is a tap target into `RoundEntryView` for `game.currentRoundNumber`.
    private func currentRow(roundNumber: Int) -> some View {
        Button {
            navigateToRoundEntry = true
        } label: {
            rowShell(roundNumber: roundNumber, tinted: true, numberColor: .indigo) {
                ForEach(participants.indices, id: \.self) { _ in
                    Text("—")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func futureRow(roundNumber: Int) -> some View {
        rowShell(roundNumber: roundNumber, tinted: false, numberColor: .secondary) {
            ForEach(participants.indices, id: \.self) { _ in
                Text("·")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(0.4)
    }

    // MARK: - Pinned total row

    private var totalRow: some View {
        HStack(spacing: 0) {
            Text("Total")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.primary)
                .frame(width: roundColumnWidth, alignment: .leading)

            ForEach(Array(participants.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 4) {
                    Text(ScoreFormat.score(totals[index]))
                        .font(.system(size: 20, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if leaderIndices.contains(index) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            dealHelperText
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            PrimaryActionButton(title: "Enter Round \(game.currentRoundNumber)") {
                navigateToRoundEntry = true
            }
        }
        .padding()
        .background(.bar)
    }

    /// "Deal **N cards** to each player" — bold only on the card-count
    /// segment, matching the mockup's `<b>` wrapping (see `GameView`'s
    /// identical helper for the iPhone footer).
    private var dealHelperText: Text {
        let n = game.currentRoundNumber
        return Text("Deal ")
            + Text("\(n) card\(n == 1 ? "" : "s")").fontWeight(.bold)
            + Text(" to each player")
    }
}
