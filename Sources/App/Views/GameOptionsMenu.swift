import SwiftUI
import SwiftData

/// Toolbar "Game Options" menu (ellipsis.circle), shown on both `GameView`
/// (iPhone) and `ScorepadGridView` (iPad) toolbars, placed before the
/// existing Undo toolbar item. Both host views only render this toolbar
/// while `game.status == .inProgress` (`GameView` swaps to
/// `FinalResultsView` once complete, and `ScorepadGridView` is only ever
/// reached from that same in-progress branch), so no extra status guard is
/// needed here.
///
/// Bundles the three in-flight adjustments a table asks for mid-game:
/// shortening (or lengthening) the game, ending it early with the current
/// totals, and seating a player who joins after the game has started.
struct GameOptionsMenu: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var showLengthSheet = false
    @State private var showEndGameConfirm = false
    @State private var showAddPlayerSheet = false
    @State private var showSettingsSheet = false

    private var completedRoundCount: Int {
        game.orderedRounds.filter { $0.phase == .complete }.count
    }

    /// Lower bound for the length editor: rounds already played can't be
    /// un-played, and a round currently mid-entry (bidding/results) can
    /// still be finished but not skipped, so the floor is whichever of
    /// "rounds completed" or "the round in progress" is higher.
    private var minRoundCount: Int {
        max(completedRoundCount, game.currentRoundNumber)
    }

    /// Upper bound: `WizardEngine`'s cap for the game's *current* seating,
    /// which can be higher than `game.totalRounds` if a player has since
    /// joined.
    private var maxRoundCount: Int {
        WizardEngine.totalRounds(playerCount: game.participants.count) ?? game.totalRounds
    }

    /// Nothing to adjust once the floor has caught up to the ceiling (e.g.
    /// every possible round has already been played).
    private var canAdjustLength: Bool {
        minRoundCount < maxRoundCount
    }

    private var canAddPlayer: Bool {
        game.participants.count < WizardEngine.maxPlayers
    }

    var body: some View {
        Menu {
            Button {
                showLengthSheet = true
            } label: {
                Label("Shorten Game…", systemImage: "slider.horizontal.3")
            }
            .disabled(!canAdjustLength)

            Button {
                showAddPlayerSheet = true
            } label: {
                Label("Add Player…", systemImage: "person.badge.plus")
            }
            .disabled(!canAddPlayer)

            Button(role: .destructive) {
                showEndGameConfirm = true
            } label: {
                Label("End Game Now", systemImage: "flag.checkered")
            }

            Divider()

            Button {
                showSettingsSheet = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .sheet(isPresented: $showLengthSheet) {
            GameLengthSheet(game: game, minRoundCount: minRoundCount, maxRoundCount: maxRoundCount)
        }
        .sheet(isPresented: $showAddPlayerSheet) {
            AddPlayerToGameSheet(game: game)
        }
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettingsSheet = false }
                        }
                    }
            }
        }
        .confirmationDialog(
            "End the game with the current totals?",
            isPresented: $showEndGameConfirm,
            titleVisibility: .visible
        ) {
            Button("End Game", role: .destructive) {
                endGameNow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rounds not played are dropped.")
        }
    }

    /// Ends the game immediately: caps `totalRounds` at what's actually been
    /// played, drops any round that never reached `.complete` (the
    /// in-progress round record, if one exists yet), then completes the
    /// game via the same `Game.complete()` every other finish path uses.
    private func endGameNow() {
        let completed = completedRoundCount
        for round in game.rounds where round.phase != .complete {
            modelContext.delete(round)
        }
        game.rounds.removeAll { $0.phase != .complete }
        game.totalRounds = completed
        game.complete()
        modelContext.saveNow()
    }
}

/// Sheet for adjusting `game.totalRounds` mid-game. Despite the menu's
/// "Shorten Game…" label this editor allows both directions — down to
/// whatever round is currently in play (rounds already played can't be
/// un-played) and up to `WizardEngine.totalRounds(playerCount:)` for the
/// game's current seating.
private struct GameLengthSheet: View {
    @Bindable var game: Game
    let minRoundCount: Int
    let maxRoundCount: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var roundCount: Int

    init(game: Game, minRoundCount: Int, maxRoundCount: Int) {
        self.game = game
        self.minRoundCount = minRoundCount
        self.maxRoundCount = maxRoundCount
        // Clamp the seed value into this sheet's own safeRange up front:
        // `game.totalRounds` can exceed `maxRoundCount` after a mid-game
        // player add inflates it past this seating's cap (e.g. 20 rounds
        // seeded, but 60÷newPlayerCount caps lower), which would otherwise
        // hand `Stepper` an out-of-range initial value.
        let lower = min(minRoundCount, maxRoundCount)
        let clampedInitial = min(max(game.totalRounds, lower), maxRoundCount)
        _roundCount = State(initialValue: clampedInitial)
    }

    private var completedRoundCount: Int {
        game.orderedRounds.filter { $0.phase == .complete }.count
    }

    /// Defensive clamp: the menu only opens this sheet when
    /// `minRoundCount < maxRoundCount`, but a degenerate `minRoundCount >
    /// maxRoundCount` would otherwise hand `Stepper` an invalid range.
    private var safeRange: ClosedRange<Int> {
        min(minRoundCount, maxRoundCount)...maxRoundCount
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScreenHeader(eyebrow: nil, title: "Game Length", subtitle: nil)
                    Text("Fewer rounds — the game ends sooner. Rounds already played stay.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    Stepper(
                        "\(roundCount) round\(roundCount == 1 ? "" : "s")",
                        value: $roundCount,
                        in: safeRange
                    )
                    .listRowBackground(Color.cardSurface)
                } footer: {
                    Text("\(completedRoundCount) round\(completedRoundCount == 1 ? "" : "s") already played.")
                        .foregroundStyle(Color.paperSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .paperBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        game.totalRounds = roundCount
        // Every remaining round was already played — finish the game now
        // instead of leaving it stranded in-progress with nothing left to
        // enter.
        if roundCount == completedRoundCount {
            game.complete()
        }
        modelContext.saveNow()
        dismiss()
    }
}

/// Sheet for seating a new player mid-game: pick an existing saved `Player`
/// not already seated, or create a brand-new one via the shared
/// `AddPlayerSheet`. Either path appends a `Participant` to `game
/// .participants` (joining at 0 points — no round contains their entries
/// yet) and, for any round still in progress, backfills a blank
/// `RoundEntry` so they can be scored starting this round.
private struct AddPlayerToGameSheet: View {
    @Bindable var game: Game

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared
    @Query(sort: \Player.name) private var players: [Player]

    @State private var showAddPlayer = false

    private var seatedPlayerIds: Set<UUID> {
        Set(game.participants.map(\.playerId))
    }

    private var availablePlayers: [Player] {
        players.filter { !seatedPlayerIds.contains($0.id) }
    }

    private var nextColorId: Int {
        let used = Set(players.map(\.colorId))
        return (0..<PlayerPalette.count).first { !used.contains($0) } ?? (players.count % PlayerPalette.count)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScreenHeader(eyebrow: nil, title: "Add Player", subtitle: nil)
                    Text("Joins at 0 points — bidding from the next round.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !availablePlayers.isEmpty {
                    Section {
                        ForEach(availablePlayers) { player in
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
                                }
                            }
                            .listRowBackground(Color.cardSurface)
                        }
                    } header: {
                        Text("Saved Players")
                            .foregroundStyle(Color.paperSecondary)
                    }
                }

                Section {
                    Button {
                        showAddPlayer = true
                    } label: {
                        Label("New Player…", systemImage: "person.badge.plus")
                    }
                    .listRowBackground(Color.cardSurface)
                }
            }
            .listStyle(.insetGrouped)
            .paperBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddPlayer) {
                AddPlayerSheet(existingNames: players.map(\.name), nextColorId: nextColorId) { name, colorId in
                    let player = Player(name: name, colorId: colorId)
                    modelContext.insert(player)
                    seat(player)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Seats `player` into the live game: appends their `Participant`
    /// snapshot, backfills a blank entry into every round still in
    /// `.bidding` (so they can be scored starting the current round if
    /// bidding hasn't closed yet), saves, and dismisses. Deliberately
    /// excludes `.results` rounds — bidding is already closed there, so a
    /// backfilled entry could never receive a bid and would linger as a
    /// phantom "0 bid, 0 tricks" hit once the round completes.
    private func seat(_ player: Player) {
        guard game.participants.count < WizardEngine.maxPlayers,
              !seatedPlayerIds.contains(player.id) else { return }

        let participant = Participant(playerId: player.id, displayNameSnapshot: player.name, colorIdSnapshot: player.colorId)
        game.participants.append(participant)

        for round in game.rounds where round.phase == .bidding {
            var updated = round.entries
            updated.append(RoundEntry(playerId: player.id, bid: nil, tricksTaken: nil))
            round.entries = updated
        }

        modelContext.saveNow()
        dismiss()
    }
}
