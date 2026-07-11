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
    @Environment(\.modelContext) private var modelContext

    @ScaledMetric(relativeTo: .body) private var allRoundsLabelSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var allRoundsCountSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var dealHelperSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var dealHelperCountSize: CGFloat = 17

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

    /// Whose deal it is this round. Prefers the inferred dealer (the last
    /// seat in `game.bidOrder(forRound:)`, once `game.firstBidderSeat` is
    /// known) so this matches `RoundEntryView`'s dealer callouts. Falls back
    /// to the old toggle-driven formula — the same one
    /// `RoundEntryView.ensureRound` seeds `Round.dealerPlayerId` with —
    /// since the current round may not be created yet.
    private var dealerName: String? {
        let n = game.currentRoundNumber
        if game.firstBidderSeat != nil {
            guard let dealerSeat = game.bidOrder(forRound: n).last, game.participants.indices.contains(dealerSeat) else { return nil }
            return game.participants[dealerSeat].displayNameSnapshot
        }
        guard game.rulesSnapshot.dealerRotationEnabled, !game.participants.isEmpty else { return nil }
        let index = (n - 1) % game.participants.count
        return game.participants[index].displayNameSnapshot
    }

    /// Up to 3 ranked mid-game trends/outliers, computed via
    /// `GameInsights.insights` from each participant's completed-round
    /// (bid, tricksTaken) history in seating order. Empty (and the Trends
    /// section omitted entirely) until at least `GameInsights.minimumRounds`
    /// rounds are complete.
    private var trendInsights: [GameInsights.Insight] {
        let lines = game.participants.map { participant -> GameInsights.PlayerLine in
            let entries = completedRounds.compactMap { round -> (bid: Int, tricksTaken: Int)? in
                guard let entry = round.entries.first(where: { $0.playerId == participant.playerId }),
                      let bid = entry.bid, let tricksTaken = entry.tricksTaken else { return nil }
                return (bid, tricksTaken)
            }
            return GameInsights.PlayerLine(name: participant.displayNameSnapshot, entries: entries)
        }
        return GameInsights.insights(players: lines, maxCount: 3)
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

            if !trendInsights.isEmpty {
                Section {
                    ForEach(Array(trendInsights.enumerated()), id: \.offset) { _, insight in
                        InsightRow(insight: insight)
                    }
                } header: {
                    Text("Trends")
                }
            }

            if !completedRounds.isEmpty {
                Section {
                    NavigationLink {
                        RoundsListView(game: game)
                    } label: {
                        HStack {
                            Text("All Rounds")
                                .font(.system(size: allRoundsLabelSize, weight: .semibold))
                            Spacer()
                            Text("\(completedRoundCount) played")
                                .font(.system(size: allRoundsCountSize, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                dealHelperText
                    .font(.system(size: dealHelperSize, weight: .semibold))
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
            ToolbarItem(placement: .navigationBarTrailing) {
                GameOptionsMenu(game: game)
            }
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
                modelContext.saveNow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be able to re-enter its bids and tricks. Totals update automatically.")
        }
        .navigationDestination(isPresented: $navigateToRoundEntry) {
            RoundEntryView(game: game, roundNumber: game.currentRoundNumber)
        }
    }

    /// "Deal **N cards** to each player" — the card-count segment is the
    /// hero (17pt heavy primary) against the rest of the line's ambient
    /// secondary/semibold styling. When a dealer is known (inferred or
    /// toggle-driven), appends " · <Name> deals".
    private var dealHelperText: Text {
        let n = game.currentRoundNumber
        var text = Text("Deal ")
            + Text("\(n) card\(n == 1 ? "" : "s")")
            .font(.system(size: dealHelperCountSize, weight: .heavy))
            .foregroundStyle(.primary)
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

        @ScaledMetric(relativeTo: .body) private var rankCircleSize: CGFloat = 30
        @ScaledMetric(relativeTo: .caption) private var rankNumberSize: CGFloat = 14
        @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 18
        @ScaledMetric(relativeTo: .caption) private var starSize: CGFloat = 10
        @ScaledMetric(relativeTo: .subheadline) private var subtitleSize: CGFloat = 13.5
        @ScaledMetric(relativeTo: .caption) private var deltaSize: CGFloat = 13
        @ScaledMetric(relativeTo: .largeTitle) private var totalSize: CGFloat = 32

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(standing.isLeader ? Color.yellow.opacity(0.22) : Color(.systemGray6))
                    Text("\(standing.rank)")
                        .font(.system(size: rankNumberSize, weight: .bold))
                        .foregroundStyle(standing.isLeader ? .yellow : .secondary)
                }
                .frame(width: rankCircleSize, height: rankCircleSize)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(standing.name)
                            .font(.system(size: nameSize, weight: .bold))
                        if standing.isLeader {
                            Image(systemName: "star.fill")
                                .font(.system(size: starSize))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(standing.isLeader ? "Leader" : "\(behind) behind")
                        .font(.system(size: subtitleSize, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if let delta = standing.delta {
                        Text(ScoreFormat.delta(delta))
                            .font(.system(size: deltaSize, weight: .bold))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(delta >= 0 ? Color.green.opacity(0.14) : Color.red.opacity(0.13))
                            .foregroundStyle(delta >= 0 ? .green : .red)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Text(ScoreFormat.score(standing.total))
                        .font(.system(size: totalSize, weight: .heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.vertical, 2)
            .frame(minHeight: 56)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    /// One row in the Trends section: an indigo SF Symbol plus
    /// `GameInsights.Insight.text`, replacing the old per-round delta rows
    /// (meaningless without names) with named mid-game trends/outliers.
    private struct InsightRow: View {
        let insight: GameInsights.Insight

        @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 20
        @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 15

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: insight.icon)
                    .foregroundStyle(.indigo)
                    .frame(width: iconWidth)
                Text(insight.text)
                    .font(.system(size: textSize, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }
}
