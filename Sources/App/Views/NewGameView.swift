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

/// Inline sheet for creating a new saved `Player`: validates a non-blank,
/// case-insensitive-unique name and auto-assigns the next unused palette id.
private struct AddPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingNames: [String]
    let nextColorId: Int
    let onAdd: (String, Int) -> Void

    @State private var name = ""
    @State private var errorMessage: String?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFieldFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(attemptAdd)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: attemptAdd)
                }
            }
            .onAppear { nameFieldFocused = true }
        }
        .presentationDetents([.height(220)])
    }

    private func attemptAdd() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a name."
            return
        }
        guard !existingNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "A player named \u{201C}\(trimmed)\u{201D} already exists."
            return
        }
        onAdd(trimmed, nextColorId)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        NewGameView()
    }
    .tint(.indigo)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
