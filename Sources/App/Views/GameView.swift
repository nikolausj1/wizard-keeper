import SwiftUI
import SwiftData

/// Screen D (iPhone): standings-first scoreboard. Ranks participants by
/// running total via `WizardEngine.placements`, shows the last-completed
/// round's delta per player, and offers "Enter Round N". Swaps to
/// `FinalResultsView` once the game is complete.
struct GameView: View {
    @Bindable var game: Game
    @State private var navigateToRoundEntry = false
    @State private var showUndoConfirm = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if game.status == .completed {
                FinalResultsView(game: game)
            } else if horizontalSizeClass == .regular {
                // iPad (iPhone is portrait-locked, so regular width means iPad):
                // the full-history scorepad grid replaces the standings list.
                ScorepadGridView(game: game)
            } else {
                inProgressBody
            }
        }
    }

    private var completedRoundCount: Int {
        game.orderedRounds.filter { $0.phase == .complete }.count
    }

    /// Same derivation `ScorepadGridView`'s iPad standings panel uses — see
    /// `StandingsCalculator` in `Theme.swift`.
    private var standings: [GameStanding] {
        StandingsCalculator.standings(for: game)
    }

    /// The current table-leading total, used to compute each non-leading
    /// player's "X behind" subtitle.
    private var leaderTotal: Int {
        standings.map(\.total).max() ?? 0
    }

    /// Completed rounds in seating order, oldest first — feeds the Rounds
    /// section below Standings.
    private var completedRounds: [Round] {
        game.orderedRounds.filter { $0.phase == .complete }
    }

    /// The most recently completed round, if any — Undo reopens exactly
    /// this one, per `Game.reopenLastCompletedRound`.
    private var lastCompletedRoundNumber: Int? {
        completedRounds.last?.roundNumber
    }

    /// Whose deal it is this round, when the house dealer-rotation rule is
    /// on — `Round.dealerPlayerId` may not exist yet for a not-yet-created
    /// current round, so this is derived straight from the same formula
    /// `RoundEntryView.ensureRound` uses.
    private var dealerName: String? {
        guard game.rulesSnapshot.dealerRotationEnabled, !game.participants.isEmpty else { return nil }
        let index = (game.currentRoundNumber - 1) % game.participants.count
        return game.participants[index].displayNameSnapshot
    }

    private var inProgressBody: some View {
        List {
            Section {
                ScreenHeader(eyebrow: nil, title: "Scoreboard", subtitle: "After Round \(completedRoundCount) of \(game.totalRounds)")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(standings) { standing in
                    StandingRow(standing: standing, leaderTotal: leaderTotal)
                }
            } header: {
                Text("Standings")
            }

            if !completedRounds.isEmpty {
                Section {
                    // Newest-first: highest completed round number at top.
                    ForEach(completedRounds.reversed(), id: \.roundNumber) { round in
                        NavigationLink(value: round.roundNumber) {
                            RoundSummaryRow(game: game, round: round)
                        }
                    }
                } header: {
                    Text("Rounds")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                dealHelperText
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                PrimaryActionButton(title: "Enter Round \(game.currentRoundNumber)") {
                    navigateToRoundEntry = true
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.bar)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if lastCompletedRoundNumber != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showUndoConfirm = true
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
            }
        }
        .confirmationDialog(
            "Reopen Round \(lastCompletedRoundNumber ?? 0)?",
            isPresented: $showUndoConfirm,
            titleVisibility: .visible
        ) {
            Button("Reopen Round", role: .destructive) {
                game.reopenLastCompletedRound()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be able to re-enter its bids and tricks. Totals update automatically.")
        }
        .navigationDestination(isPresented: $navigateToRoundEntry) {
            RoundEntryView(game: game, roundNumber: game.currentRoundNumber)
        }
        .navigationDestination(for: Int.self) { roundNumber in
            RoundEntryView(game: game, roundNumber: roundNumber)
        }
    }

    /// "Deal **N cards** to each player" — bold only on the card-count
    /// segment, matching the mockup's `<b>` wrapping. When dealer rotation
    /// is on, appends " · <Name> deals".
    private var dealHelperText: Text {
        let n = game.currentRoundNumber
        var text = Text("Deal ")
            + Text("\(n) card\(n == 1 ? "" : "s")").fontWeight(.bold)
            + Text(" to each player")
        if let dealerName {
            text = text + Text(" · \(dealerName) deals")
        }
        return text
    }

    /// One standings row: rank badge, name, "Leader"/"X behind" subtitle,
    /// last-round delta chip, and the running total (the biggest text on
    /// screen).
    private struct StandingRow: View {
        let standing: GameStanding
        let leaderTotal: Int

        private var behind: Int { max(leaderTotal - standing.total, 0) }

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(standing.isLeader ? Color.yellow.opacity(0.22) : Color(.systemGray6))
                    Text("\(standing.rank)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(standing.isLeader ? .yellow : .secondary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(standing.name)
                            .font(.system(size: 18, weight: .bold))
                        if standing.isLeader {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(standing.isLeader ? "Leader" : "\(behind) behind")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if let delta = standing.delta {
                        Text(ScoreFormat.delta(delta))
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(delta >= 0 ? Color.green.opacity(0.14) : Color.red.opacity(0.13))
                            .foregroundStyle(delta >= 0 ? .green : .red)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Text(ScoreFormat.score(standing.total))
                        .font(.system(size: 32, weight: .heavy))
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 2)
            .frame(minHeight: 56)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    /// One row in the Rounds section: round label plus every player's
    /// delta for that round, seating order, monospaced and green/red.
    private struct RoundSummaryRow: View {
        let game: Game
        let round: Round

        private var deltaText: Text {
            let parts = game.participants.map { participant -> Text in
                let delta = round.score(for: participant.playerId) ?? 0
                return Text(ScoreFormat.delta(delta)).foregroundStyle(delta >= 0 ? .green : .red)
            }
            guard var combined = parts.first else { return Text("") }
            for part in parts.dropFirst() {
                combined = combined + Text(" \u{00B7} ").foregroundStyle(.secondary) + part
            }
            return combined
        }

        var body: some View {
            HStack {
                Text("Round \(round.roundNumber)")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                deltaText
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .padding(.vertical, 2)
            .frame(minHeight: 44)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }
}
