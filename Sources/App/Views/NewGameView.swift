import SwiftUI
import SwiftData

/// Screen B: pick 3–6 saved players, seat them in order, optionally shorten
/// the game, then create the `Game` and hand off to `GameView`.
struct NewGameView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]

    @State private var selectedPlayerIDs: [UUID] = []
    @State private var showAddPlayer = false

    @State private var quickGame = false
    @State private var quickRoundCount = 1

    @State private var createdGame: Game?
    @State private var navigateToGame = false

    private var selectedPlayers: [Player] {
        selectedPlayerIDs.compactMap { id in players.first { $0.id == id } }
    }

    private var fullRoundCount: Int? {
        WizardEngine.totalRounds(playerCount: selectedPlayerIDs.count)
    }

    private var effectiveRoundCount: Int? {
        guard let full = fullRoundCount else { return nil }
        return quickGame ? min(max(quickRoundCount, 1), full) : full
    }

    private var canStart: Bool {
        (WizardEngine.minPlayers...WizardEngine.maxPlayers).contains(selectedPlayerIDs.count)
            && effectiveRoundCount != nil
    }

    private var nextColorId: Int {
        let used = Set(players.map(\.colorId))
        return (0..<PlayerPalette.count).first { !used.contains($0) } ?? (players.count % PlayerPalette.count)
    }

    var body: some View {
        List {
            Section {
                if selectedPlayerIDs.isEmpty {
                    Text("Select 3–6 players below to seat them for this game.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedPlayers) { player in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(PlayerPalette.color(player.colorId))
                                .frame(width: 12, height: 12)
                            Text(player.name)
                        }
                    }
                    .onMove(perform: moveSelected)
                }
            } header: {
                Text("Seating Order")
            } footer: {
                if !selectedPlayerIDs.isEmpty {
                    Text("Drag to reorder. First seat deals first.")
                }
            }

            Section {
                ForEach(players) { player in
                    Button {
                        toggle(player)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(PlayerPalette.color(player.colorId))
                                .frame(width: 12, height: 12)
                            Text(player.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedPlayerIDs.contains(player.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.indigo)
                                    .font(.body.weight(.semibold))
                            }
                        }
                    }
                }

                Button {
                    showAddPlayer = true
                } label: {
                    Label("Add Player", systemImage: "person.badge.plus")
                }
            } header: {
                Text("Saved Players")
            }

            Section {
                Toggle("Quick Game", isOn: $quickGame.animation())
                if quickGame, let full = fullRoundCount {
                    Stepper(
                        "\(quickRoundCount) round\(quickRoundCount == 1 ? "" : "s")",
                        value: $quickRoundCount,
                        in: 1...full
                    )
                }
            } footer: {
                if let count = effectiveRoundCount {
                    Text("\(selectedPlayerIDs.count) players · \(count) rounds")
                } else {
                    Text("Select 3–6 players to see the round count.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("New Game")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
                    .disabled(selectedPlayerIDs.count < 2)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: startGame) {
                Text("Start Game")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.large)
            .disabled(!canStart)
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showAddPlayer) {
            AddPlayerSheet(existingNames: players.map(\.name), nextColorId: nextColorId) { name, colorId in
                let player = Player(name: name, colorId: colorId)
                modelContext.insert(player)
                selectedPlayerIDs.append(player.id)
            }
        }
        .navigationDestination(isPresented: $navigateToGame) {
            if let createdGame {
                GameView(game: createdGame)
            }
        }
        .onChange(of: selectedPlayerIDs.count) {
            if quickGame, let full = fullRoundCount {
                quickRoundCount = min(quickRoundCount, full)
            }
        }
        .task { applyDefaultsFromSettings() }
    }

    /// Seeds the Quick Game toggle/stepper from `AppSettings` as one-time
    /// initial state (mirroring the model's own default-length rule) —
    /// this never overwrites a value the player has since changed, since
    /// `.task` runs once when this freshly pushed view first appears.
    private func applyDefaultsFromSettings() {
        guard let settings = try? AppSettings.fetchOrCreate(in: modelContext) else { return }
        if !settings.useFullLength {
            quickGame = true
            quickRoundCount = settings.customRoundCount ?? 10
        }
    }

    private func toggle(_ player: Player) {
        if let index = selectedPlayerIDs.firstIndex(of: player.id) {
            selectedPlayerIDs.remove(at: index)
        } else {
            guard selectedPlayerIDs.count < WizardEngine.maxPlayers else { return }
            selectedPlayerIDs.append(player.id)
        }
    }

    private func moveSelected(from source: IndexSet, to destination: Int) {
        selectedPlayerIDs.move(fromOffsets: source, toOffset: destination)
    }

    private func startGame() {
        guard canStart, let roundCount = effectiveRoundCount else { return }
        let participants = selectedPlayers.map {
            Participant(playerId: $0.id, displayNameSnapshot: $0.name, colorIdSnapshot: $0.colorId)
        }
        let rulesSnapshot = (try? AppSettings.fetchOrCreate(in: modelContext).makeRulesSnapshot())
            ?? RulesSnapshot(hookRuleEnabled: false, trickTotalCheckEnabled: true, dealerRotationEnabled: false)
        let game = Game(participants: participants, totalRounds: roundCount, rulesSnapshot: rulesSnapshot)
        modelContext.insert(game)
        createdGame = game
        navigateToGame = true
    }
}

#Preview {
    NavigationStack {
        NewGameView()
    }
    .tint(.indigo)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
