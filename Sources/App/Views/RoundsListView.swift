import SwiftUI
import SwiftData

/// Pushed from `GameView`'s "All Rounds" row: the per-round record WITH
/// NAMES, newest-first, for review and editing — replaces the old inline
/// Rounds section (per-round deltas with no names, which was meaningless).
/// Each row uses the same compact per-participant cell pattern as
/// `GameDetailView`'s `RoundBreakdownRow`, and taps through to
/// `RoundEntryView` in edit mode (the round is already `.complete`).
struct RoundsListView: View {
    @Bindable var game: Game
    @ObservedObject private var themeManager = ThemeManager.shared

    /// Completed rounds, newest-first — the reverse of seating/round order,
    /// so the most recently played round is always at the top.
    private var completedRounds: [Round] {
        game.orderedRounds.filter { $0.phase == .complete }.reversed()
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(title: "Rounds", subtitle: "Tap a round to edit it")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if completedRounds.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No rounds yet",
                        systemImage: "list.number",
                        description: Text("Completed rounds will show up here.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(completedRounds, id: \.roundNumber) { round in
                        NavigationLink {
                            RoundEntryView(game: game, roundNumber: round.roundNumber)
                        } label: {
                            RoundRow(round: round, participants: game.participants)
                        }
                        .listRowBackground(Color.cardSurface)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One round's per-player bid/took/delta breakdown, laid out the same way
/// as `GameDetailView`'s `RoundBreakdownRow` — an evenly spaced row of
/// compact cells so 4-6 players fit an iPhone width.
private struct RoundRow: View {
    let round: Round
    let participants: [Participant]
    @ObservedObject private var themeManager = ThemeManager.shared

    private var cellSpacing: CGFloat {
        participants.count >= 6 ? 4 : 8
    }

    @ScaledMetric(relativeTo: .subheadline) private var roundLabelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var roundLabelWidth: CGFloat = 28
    @ScaledMetric(relativeTo: .caption) private var nameSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var bidTakenSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var deltaSize: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("R\(round.roundNumber)")
                .font(.system(size: roundLabelSize, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: roundLabelWidth, alignment: .leading)

            HStack(spacing: cellSpacing) {
                ForEach(participants, id: \.playerId) { participant in
                    participantCell(for: participant)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 6)
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
                .font(.system(size: nameSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let bid, let tricksTaken {
                Text("\(bid)\u{2013}\(tricksTaken)")
                    .font(.system(size: bidTakenSize, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("\u{2013}")
                    .font(.system(size: bidTakenSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let delta {
                Text(ScoreFormat.delta(delta))
                    .font(.system(size: deltaSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(delta >= 0 ? Color.feltGreen : Color.terracotta)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("\u{2013}")
                    .font(.system(size: deltaSize, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        RoundsListView(game: Game(
            participants: [],
            totalRounds: 15,
            rulesSnapshot: RulesSnapshot(hookRuleEnabled: false, trickTotalCheckEnabled: true, dealerRotationEnabled: false)
        ))
    }
    .tint(.feltGreen)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
