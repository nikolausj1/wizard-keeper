import SwiftUI
import SwiftData

/// Screen A: app entry point. Offers Resume (if a game is in progress),
/// New Game, and placeholder navigation to History/Players/Settings.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var inProgressGame: Game?
    @State private var navigateToNewGame = false
    @State private var showAbandonConfirm = false

    var body: some View {
        List {
            if let game = inProgressGame {
                Section {
                    NavigationLink {
                        GameView(game: game)
                    } label: {
                        ResumeGameRow(game: game)
                    }
                } header: {
                    Text("Continue")
                        .foregroundStyle(Color.paperSecondary)
                }
            } else {
                Section {
                    Text("Ready to keep score for your next Wizard game?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }

            Section {
                Button {
                    startNewGameTapped()
                } label: {
                    Label("New Game", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .tint(.feltGreen)
            }

            Section {
                NavigationLink("History") {
                    HistoryView()
                }
                NavigationLink("Players") {
                    PlayersView()
                }
                NavigationLink("Settings") {
                    SettingsView()
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .navigationTitle("Wizard Keeper")
        .navigationDestination(isPresented: $navigateToNewGame) {
            NewGameView()
        }
        .confirmationDialog(
            "End current game?",
            isPresented: $showAbandonConfirm,
            titleVisibility: .visible
        ) {
            Button("Abandon Game", role: .destructive) {
                abandonInProgressGame()
                navigateToNewGame = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starting a new game ends the game currently in progress. This can't be undone.")
        }
        .onAppear(perform: refreshInProgress)
    }

    private func startNewGameTapped() {
        if inProgressGame != nil {
            showAbandonConfirm = true
        } else {
            navigateToNewGame = true
        }
    }

    private func refreshInProgress() {
        inProgressGame = try? Game.fetchInProgress(in: modelContext)
    }

    private func abandonInProgressGame() {
        guard let game = inProgressGame else { return }
        modelContext.delete(game)
        modelContext.saveNow()
        inProgressGame = nil
    }
}

/// Resume-card content: seated players and current round progress.
private struct ResumeGameRow: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Resume Game")
                .font(.headline)
            Text(game.participants.map(\.displayNameSnapshot).joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("Round \(game.currentRoundNumber) of \(game.totalRounds)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.feltGreen)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .tint(.feltGreen)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
