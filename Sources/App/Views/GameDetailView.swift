import SwiftUI
import SwiftData
import UIKit

/// Screen F detail: a completed game's final standings plus its per-round
/// breakdown of bids/tricks/deltas. Read-only — editing past rounds is
/// Phase 6.
struct GameDetailView: View {
    let game: Game

    @State private var recapImage: UIImage?

    // Dynamic Type: sizes below are `@ScaledMetric`-driven rather than
    // fixed literals so this screen scales with the system text size.
    @ScaledMetric(relativeTo: .body) private var standingNameSize: CGFloat = 18
    @ScaledMetric(relativeTo: .largeTitle) private var standingTotalSize: CGFloat = 30

    private struct Standing: Identifiable {
        let id: UUID
        let rank: Int
        let name: String
        let total: Int
        let isWinner: Bool
    }

    private var standings: [Standing] {
        let participants = game.participants
        let totals = participants.map { game.runningTotal(for: $0.playerId) }
        let ranks = WizardEngine.placements(totals: totals)
        let winnerIds = Set(game.winnerPlayerIds)

        return participants.enumerated().map { index, participant in
            (seat: index, standing: Standing(
                id: participant.playerId,
                rank: ranks[index],
                name: participant.displayNameSnapshot,
                total: totals[index],
                isWinner: winnerIds.contains(participant.playerId)
            ))
        }
        // Stable tie ordering: rank first, then seating order.
        .sorted { ($0.standing.rank, $0.seat) < ($1.standing.rank, $1.seat) }
        .map(\.standing)
    }

    private var winnerNames: String {
        standings.filter(\.isWinner).map(\.name).joined(separator: " & ")
    }

    private var titleText: String {
        winnerNames.isEmpty ? "Game" : "\(winnerNames) won"
    }

    private var dateText: String {
        guard let date = game.completedAt else { return "Unknown date" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var completedRounds: [Round] {
        game.orderedRounds.filter { $0.phase == .complete }
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(
                    title: titleText,
                    subtitle: "\(dateText) \u{00B7} \(game.totalRounds) round\(game.totalRounds == 1 ? "" : "s")"
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if standings.isEmpty {
                Section {
                    Text("No player data available for this game.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(standings) { standing in
                        standingRow(standing)
                    }
                } header: {
                    Text("Final Standings")
                        .foregroundStyle(Color.paperSecondary)
                }
            }

            if completedRounds.isEmpty {
                Section {
                    Text("No rounds were recorded for this game.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Rounds")
                        .foregroundStyle(Color.paperSecondary)
                }
            } else {
                Section {
                    ForEach(completedRounds, id: \.roundNumber) { round in
                        RoundBreakdownRow(round: round, participants: game.participants)
                    }
                } header: {
                    Text("Rounds")
                        .foregroundStyle(Color.paperSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let recapImage {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(
                        item: Image(uiImage: recapImage),
                        preview: SharePreview("Game Recap", image: Image(uiImage: recapImage))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            if recapImage == nil, game.status == .completed {
                recapImage = RecapCardRenderer.renderRecapImage(for: game)
            }
        }
    }

    private func standingRow(_ standing: Standing) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(standing.isWinner ? Color.brassGold.opacity(0.22) : Color(.systemGray6))
                Text("\(standing.rank)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(standing.isWinner ? Color.brassGold : .secondary)
            }
            .frame(width: 34, height: 34)

            HStack(spacing: 4) {
                Text(standing.name)
                    .font(.system(size: standingNameSize, weight: .semibold))
                if standing.isWinner {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.brassGold)
                }
            }

            Spacer()

            Text(ScoreFormat.score(standing.total))
                .font(.system(size: standingTotalSize, weight: .heavy))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

/// One round's per-player bid/tricks/delta breakdown, laid out as an evenly
/// spaced row of compact cells so 4-6 players fit an iPhone width.
private struct RoundBreakdownRow: View {
    let round: Round
    let participants: [Participant]

    // Dynamic Type: sizes below are `@ScaledMetric`-driven rather than
    // fixed literals so this screen scales with the system text size.
    @ScaledMetric(relativeTo: .caption) private var roundLabelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var cellNameSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var cellScoreSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var cellDeltaSize: CGFloat = 14

    private var cellSpacing: CGFloat {
        participants.count >= 6 ? 4 : 8
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("R\(round.roundNumber)")
                .font(.system(size: roundLabelSize, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            HStack(spacing: cellSpacing) {
                ForEach(participants, id: \.playerId) { participant in
                    participantCell(for: participant)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func firstName(_ fullName: String) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    @ViewBuilder
    private func participantCell(for participant: Participant) -> some View {
        let entry = round.entries.first { $0.playerId == participant.playerId }
        let bid = entry?.bid
        let tricksTaken = entry?.tricksTaken
        let delta = round.score(for: participant.playerId)

        VStack(spacing: 2) {
            Text(firstName(participant.displayNameSnapshot))
                .font(.system(size: cellNameSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let bid, let tricksTaken {
                Text("\(bid)\u{2013}\(tricksTaken)")
                    .font(.system(size: cellScoreSize, weight: .semibold, design: .monospaced))
            } else {
                Text("\u{2013}")
                    .font(.system(size: cellScoreSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let delta {
                Text(ScoreFormat.delta(delta))
                    .font(.system(size: cellDeltaSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(delta >= 0 ? Color.feltGreen : Color.terracotta)
            } else {
                Text("\u{2013}")
                    .font(.system(size: cellDeltaSize, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        GameDetailView(game: Game(
            participants: [],
            totalRounds: 15,
            rulesSnapshot: RulesSnapshot(hookRuleEnabled: false, trickTotalCheckEnabled: true, dealerRotationEnabled: false)
        ))
    }
    .tint(.feltGreen)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
