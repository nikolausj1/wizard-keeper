import SwiftUI
import SwiftData

/// App root: a single `NavigationStack` rooted at `HomeView`, tinted with
/// the one accent color app-wide — felt green, per the "Warm Table" design
/// direction.
///
/// Sim-verify support: `simctl` can't tap, so a `-uiScreen <name>` launch
/// argument (paired with the `-demo*` seeding args, which force an
/// in-memory store) lets a screenshot land directly on any screen:
/// `newGame`, `game`, `bidding`, `results`, `final`, `history`, `players`,
/// `gameDetail` (pair with `-demoHistory`), `playerProfile` (pair with
/// `-demoHistory`), `settings`, or `editRound` (pair with `-demoMidGame`;
/// round 5 is complete in that seed, so it lands in edit mode).
struct RootView: View {
    private static let uiScreen = WizardKeeperApp.launchArgumentValue(
        "-uiScreen", in: ProcessInfo.processInfo.arguments
    )

    // Singleton `AppSettings` record — see `AppSettings.fetchOrCreate`. A
    // plain `@Query` (no predicate needed) is enough to observe it live so
    // toggling "Appearance" in `SettingsView` recolors the whole app
    // immediately.
    @Query private var settingsRecords: [AppSettings]

    private var preferredColorScheme: ColorScheme? {
        switch settingsRecords.first?.appearance ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        NavigationStack {
            rootContent
        }
        .tint(.feltGreen)
        .preferredColorScheme(preferredColorScheme)
        .onAppear(perform: fireAnnouncerTestIfNeeded)
    }

    /// Verification hook for the announcer feature: `-announcerTest`
    /// (combinable with any `-uiScreen`) fires a synthetic two-insight
    /// round-update broadcast one second after launch and prints the
    /// resolved/missing segment counts, so the lead can confirm clip
    /// resolution ran from `simctl` console logs alone — no tapping
    /// required.
    private func fireAnnouncerTestIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-announcerTest") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let insights = [
                GameInsights.Insight(
                    icon: "snowflake",
                    text: "Announcer test",
                    priority: 0,
                    kind: .coldStreak,
                    playerName: "Justin",
                    value: 3
                ),
                GameInsights.Insight(
                    icon: "checkmark.seal.fill",
                    text: "Announcer test",
                    priority: 0,
                    kind: .perfect,
                    playerName: "Kelly",
                    value: 7
                ),
            ]
            let segments = AnnouncerPlayer.shared.announceRoundUpdate(insights: insights, voice: .charlie, style: .scorched)
            print("announcer test fired, segments: \(segments)")
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch Self.uiScreen {
        case "newGame":
            NewGameView()
        case "game", "final":
            DemoGameHost { GameView(game: $0) }
        case "bidding":
            DemoGameHost { RoundEntryView(game: $0, roundNumber: $0.currentRoundNumber) }
        case "results":
            DemoGameHost { RoundEntryView(game: $0, roundNumber: 8) }
        case "history":
            HistoryView()
        case "players":
            PlayersView()
        case "gameDetail":
            DemoCompletedGameHost { GameDetailView(game: $0) }
        case "playerProfile":
            DemoPlayerHost(name: "Kelly") { PlayerProfileView(player: $0) }
        case "settings":
            SettingsView()
        case "editRound":
            DemoGameHost { RoundEntryView(game: $0, roundNumber: 5) }
        default:
            HomeView()
        }
    }
}

/// Fetches the seeded demo game (any status) and hands it to `content`.
/// Only reachable via `-uiScreen`; shows a clear fallback if seeding failed.
private struct DemoGameHost<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @ViewBuilder let content: (Game) -> Content

    var body: some View {
        if let game = try? modelContext.fetch(FetchDescriptor<Game>()).first {
            content(game)
        } else {
            ContentUnavailableView(
                "No demo game seeded",
                systemImage: "exclamationmark.triangle",
                description: Text("Pass -demoMidGame or -demoFinal alongside -uiScreen.")
            )
        }
    }
}

/// Fetches the most recently completed demo game (seeded via
/// `-demoHistory`) and hands it to `content`. Only reachable via
/// `-uiScreen gameDetail`; shows a clear fallback if seeding failed.
private struct DemoCompletedGameHost<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @ViewBuilder let content: (Game) -> Content

    var body: some View {
        let completed = (try? modelContext.fetch(FetchDescriptor<Game>()))?
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        if let game = completed?.first {
            content(game)
        } else {
            ContentUnavailableView(
                "No completed demo game seeded",
                systemImage: "exclamationmark.triangle",
                description: Text("Pass -demoHistory alongside -uiScreen gameDetail.")
            )
        }
    }
}

/// Fetches the demo `Player` named `name` (seeded via `-demoHistory`) and
/// hands it to `content`. Only reachable via `-uiScreen playerProfile`;
/// shows a clear fallback if seeding failed or the name isn't found.
private struct DemoPlayerHost<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    let name: String
    @ViewBuilder let content: (Player) -> Content

    var body: some View {
        let players = try? modelContext.fetch(FetchDescriptor<Player>())
        if let player = players?.first(where: { $0.name == name }) {
            content(player)
        } else {
            ContentUnavailableView(
                "No demo player named \(name)",
                systemImage: "exclamationmark.triangle",
                description: Text("Pass -demoHistory alongside -uiScreen playerProfile.")
            )
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
