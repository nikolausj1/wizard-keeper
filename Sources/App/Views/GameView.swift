import SwiftUI
import SwiftData

/// Screen D (iPhone): standings-first scoreboard. Ranks participants by
/// running total via `WizardEngine.placements`, shows the last-completed
/// round's delta per player, and offers "Enter Round N". Swaps to
/// `FinalResultsView` once the game is complete.
struct GameView: View {
    @Bindable var game: Game
    @State private var navigateToRoundEntry = false

    var body: some View {
        Group {
            if game.status == .completed {
                FinalResultsView(game: game)
            } else {
                inProgressBody
            }
        }
    }

    private struct Standing: Identifiable {
        let id: UUID
        let rank: Int
        let name: String
        let colorId: Int
        let total: Int
        let delta: Int?
        let isLeader: Bool
    }

    private var lastCompletedRound: Round? {
        game.orderedRounds.last { $0.phase == .complete }
    }

    private var completedRoundCount: Int {
        game.orderedRounds.filter { $0.phase == .complete }.count
    }

    private var standings: [Standing] {
        let participants = game.participants
        let totals = participants.map { game.runningTotal(for: $0.playerId) }
        let ranks = WizardEngine.placements(totals: totals)
        let leaders = lastCompletedRound == nil ? [] : Set(WizardEngine.winners(totals: totals))
        let lastRound = lastCompletedRound

        return participants.enumerated().map { index, participant in
            (seat: index, standing: Standing(
                id: participant.playerId,
                rank: ranks[index],
                name: participant.displayNameSnapshot,
                colorId: participant.colorIdSnapshot,
                total: totals[index],
                delta: lastRound?.score(for: participant.playerId),
                isLeader: leaders.contains(index)
            ))
        }
        // Swift's sort isn't guaranteed stable — break rank ties by seating
        // order explicitly so tied players never jump around between rounds.
        .sorted { ($0.standing.rank, $0.seat) < ($1.standing.rank, $1.seat) }
        .map(\.standing)
    }

    private var inProgressBody: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(standings) { standing in
                        StandingRow(standing: standing)
                    }
                } header: {
                    Text("Standings")
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top) {
                Text("After Round \(completedRoundCount) of \(game.totalRounds)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 2)
            }

            VStack(spacing: 10) {
                Text("Deal \(game.currentRoundNumber) card\(game.currentRoundNumber == 1 ? "" : "s") to each player")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    navigateToRoundEntry = true
                } label: {
                    Text("Enter Round \(game.currentRoundNumber)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Scoreboard")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $navigateToRoundEntry) {
            RoundEntryView(game: game, roundNumber: game.currentRoundNumber)
        }
    }

    /// One standings row: rank badge, color dot, name, last-round delta
    /// chip, and the running total (the biggest text on screen).
    private struct StandingRow: View {
        let standing: Standing

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(standing.isLeader ? Color.yellow.opacity(0.22) : Color(.systemGray6))
                    Text("\(standing.rank)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(standing.isLeader ? .yellow : .secondary)
                }
                .frame(width: 28, height: 28)

                Circle()
                    .fill(PlayerPalette.color(standing.colorId))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(standing.name)
                            .font(.body.weight(.semibold))
                        if standing.isLeader {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                    if standing.isLeader {
                        Text("Leader")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if let delta = standing.delta {
                        Text(ScoreFormat.delta(delta))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(delta >= 0 ? Color.green.opacity(0.14) : Color.red.opacity(0.13))
                            .foregroundStyle(delta >= 0 ? .green : .red)
                            .clipShape(Capsule())
                    }
                    Text("\(standing.total)")
                        .font(.system(size: 26, weight: .heavy))
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
        }
    }
}
