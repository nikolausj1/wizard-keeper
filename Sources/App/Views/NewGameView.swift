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
                    .onDelete(perform: unseatSelected)
                }
            } header: {
                Text("Seating Order")
            } footer: {
                if !selectedPlayerIDs.isEmpty {
                    Text("Drag to reorder — first seat deals first. Swipe to remove.")
                }
            }

            // Seated players move OUT of this list (no name appears twice);
            // removing them from Seating Order puts them back here.
            Section {
                ForEach(unseatedPlayers) { player in
                    Button {
                        seat(player)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(PlayerPalette.color(player.colorId))
                                .frame(width: 12, height: 12)
                            Text(player.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.feltGreen)
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
            } footer: {
                if !players.isEmpty && unseatedPlayers.isEmpty {
                    Text("Everyone's seated.")
                }
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
        .listSectionSpacing(.compact)
        .paperBackground()
        .navigationTitle("New Game")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
                    .disabled(selectedPlayerIDs.count < 2)
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryActionButton(title: "Start Game", isDisabled: !canStart, action: startGame)
                .padding()
                .background(.bar)
        }
        .sheet(isPresented: $showAddPlayer) {
            AddPlayerSheet(existingNames: players.map(\.name), nextColorId: nextColorId) { name, colorId in
                let player = Player(name: name, colorId: colorId)
                modelContext.insert(player)
                // Seat the new player if there's room; otherwise they stay
                // in Saved Players (table is already full at 6).
                seat(player)
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

    /// Saved players not yet seated — the only ones shown in the Saved
    /// Players section, so no name ever appears in both lists.
    private var unseatedPlayers: [Player] {
        players.filter { !selectedPlayerIDs.contains($0.id) }
    }

    private func seat(_ player: Player) {
        guard selectedPlayerIDs.count < WizardEngine.maxPlayers,
              !selectedPlayerIDs.contains(player.id) else { return }
        withAnimation {
            selectedPlayerIDs.append(player.id)
        }
    }

    private func unseatSelected(at offsets: IndexSet) {
        withAnimation {
            selectedPlayerIDs.remove(atOffsets: offsets)
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
        modelContext.saveNow()
        navigateToGame = true
    }
}

#Preview {
    NavigationStack {
        NewGameView()
    }
    .tint(.feltGreen)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
