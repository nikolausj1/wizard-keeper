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
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .paperBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One row: date, seated player names, and the winner line.
private struct HistoryRow: View {
    let game: Game

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateText)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)

            if !playerNames.isEmpty {
                Text(playerNames)
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !winners.isEmpty, let winnerScore {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(winners.map(\.displayNameSnapshot).joined(separator: " & "))
                        .font(.system(size: 15, weight: .bold))
                    Text("\u{00B7}")
                        .foregroundStyle(.secondary)
                    Text(ScoreFormat.score(winnerScore))
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                }
            } else {
                Text("No winner recorded")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .tint(.indigo)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
