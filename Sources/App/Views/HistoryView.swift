import SwiftUI
import SwiftData

/// Screen F: list of completed games, newest first. Tap a row to see the
/// full game detail (final standings + per-round breakdown).
///
/// `Game.statusRaw` is private to the model, so this view can't filter via
/// `#Predicate` — it fetches every `Game` and filters/sorts on the public
/// `status` computed property instead. Game history is small (dozens to a
/// few hundred rows at most), so this is cheap enough to do in-memory.
struct HistoryView: View {
    @Query private var allGames: [Game]
    @ObservedObject private var themeManager = ThemeManager.shared

    private var completedGames: [Game] {
        allGames
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(
                    title: "History",
                    subtitle: "\(completedGames.count) completed game\(completedGames.count == 1 ? "" : "s")"
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if completedGames.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No games yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your finished games will show up here.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(completedGames) { game in
                        NavigationLink {
                            GameDetailView(game: game)
                        } label: {
                            HistoryRow(game: game)
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

/// One row: date, seated player names, and the winner line.
private struct HistoryRow: View {
    let game: Game
    @ObservedObject private var themeManager = ThemeManager.shared

    private var participants: [Participant] { game.participants }

    private var playerNames: String {
        participants.map(\.displayNameSnapshot).joined(separator: ", ")
    }

    private var winners: [Participant] {
        let winnerIds = Set(game.winnerPlayerIds)
        return participants.filter { winnerIds.contains($0.playerId) }
    }

    private var winnerScore: Int? {
        guard let first = winners.first else { return nil }
        return game.runningTotal(for: first.playerId)
    }

    private var dateText: String {
        guard let date = game.completedAt else { return "Unknown date" }
        return date.formatted(.relative(presentation: .named))
    }

    @ScaledMetric(relativeTo: .subheadline) private var dateSize: CGFloat = 13.5
    @ScaledMetric(relativeTo: .subheadline) private var namesSize: CGFloat = 15.5
    @ScaledMetric(relativeTo: .body) private var winnerLineSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateText)
                .font(.system(size: dateSize, weight: .medium))
                .foregroundStyle(.secondary)

            if !playerNames.isEmpty {
                Text(playerNames)
                    .font(.system(size: namesSize, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !winners.isEmpty, let winnerScore {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.brassGold)
                    Text(winners.map(\.displayNameSnapshot).joined(separator: " & "))
                        .font(.system(size: winnerLineSize, weight: .bold))
                    Text("\u{00B7}")
                        .foregroundStyle(.secondary)
                    Text(ScoreFormat.score(winnerScore))
                        .font(.system(size: winnerLineSize, weight: .bold))
                        .monospacedDigit()
                }
            } else {
                Text("No winner recorded")
                    .font(.system(size: winnerLineSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .tint(.feltGreen)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
