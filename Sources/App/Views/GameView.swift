import SwiftUI
import SwiftData

/// Screen D (iPhone): standings-first scoreboard. Ranks participants by
/// running total via `WizardEngine.placements`, shows the last-completed
/// round's delta per player, and offers "Enter Round N". Swaps to
/// `FinalResultsView` once the game is complete.
struct GameView: View {
    @Bindable var game: Game
    @State private var navigateToRoundEntry = false
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
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                dealHelperText
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                PrimaryActionButton(title: "Enter Round \(game.currentRoundNumber)") {
                    navigateToRoundEntry = true
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToRoundEntry) {
            RoundEntryView(game: game, roundNumber: game.currentRoundNumber)
        }
    }

    /// "Deal **N cards** to each player" — bold only on the card-count
    /// segment, matching the mockup's `<b>` wrapping.
    private var dealHelperText: Text {
        let n = game.currentRoundNumber
        return Text("Deal ")
            + Text("\(n) card\(n == 1 ? "" : "s")").fontWeight(.bold)
            + Text(" to each player")
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

                VStack(alignment: .leading, spacing: 2) {
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

                VStack(alignment: .trailing, spacing: 3) {
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
            .padding(.vertical, 8)
            .frame(minHeight: 68)
        }
    }
}
