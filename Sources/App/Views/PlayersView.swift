import SwiftUI
import SwiftData

/// Screen G: roster of saved players with a headline win count each. Tap a
/// row for the full lifetime-stats profile; "+" adds a new saved player
/// (shares `AddPlayerSheet` with `NewGameView`'s seating flow).
struct PlayersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]
    @Query private var allGames: [Game]
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var showAddPlayer = false

    private var completedGames: [Game] {
        allGames.filter { $0.status == .completed }
    }

    private var nextColorId: Int {
        let used = Set(players.map(\.colorId))
        return (0..<PlayerPalette.count).first { !used.contains($0) } ?? (players.count % PlayerPalette.count)
    }

    private func winCount(for player: Player) -> Int {
        completedGames.filter { $0.winnerPlayerIds.contains(player.id) }.count
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(title: "Players", subtitle: "\(players.count) saved")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if players.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No players yet",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add the people you play with.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(players) { player in
                        NavigationLink {
                            PlayerProfileView(player: player)
                        } label: {
                            PlayerRow(player: player, wins: winCount(for: player))
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddPlayer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPlayer) {
            AddPlayerSheet(existingNames: players.map(\.name), nextColorId: nextColorId) { name, colorId in
                let player = Player(name: name, colorId: colorId)
                modelContext.insert(player)
            }
        }
    }
}

/// One roster row: color dot, name, and lifetime win count.
private struct PlayerRow: View {
    let player: Player
    let wins: Int
    @ObservedObject private var themeManager = ThemeManager.shared

    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var winsSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(PlayerPalette.color(player.colorId))
                .frame(width: dotSize, height: dotSize)

            Text(player.name)
                .font(.system(size: nameSize, weight: .bold))

            Spacer()

            Text("\(wins) win\(wins == 1 ? "" : "s")")
                .font(.system(size: winsSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

#Preview {
    NavigationStack {
        PlayersView()
    }
    .tint(.feltGreen)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
