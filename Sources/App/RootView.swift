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
/// round 5 is complete in that seed, so it lands in edit mode). `game`
/// paired with `-demoFreshGame` instead of `-demoMidGame`/`-demoFinal`
/// lands on a zero-round in-progress game, showing the Trends section's
/// pregame path.
struct RootView: View {
    private static let uiScreen = WizardKeeperApp.launchArgumentValue(
        "-uiScreen", in: ProcessInfo.processInfo.arguments
    )

    /// Sim-verify hook: `-uiTheme parchment|cardTable|walnut` forces a
    /// color theme for screenshots, overriding the persisted setting —
    /// same spirit as `-uiScreen`.
    private static let uiTheme: AppTheme? = {
        switch WizardKeeperApp.launchArgumentValue("-uiTheme", in: ProcessInfo.processInfo.arguments) {
        case "parchment": .parchment
        case "cardTable": .cardTable
        case "walnut": .walnut
        default: nil
        }
    }()

    // Singleton `AppSettings` record — see `AppSettings.fetchOrCreate`. A
    // plain `@Query` (no predicate needed) is enough to observe it live so
    // toggling "Appearance" in `SettingsView` recolors the whole app
    // immediately.
    @Query private var settingsRecords: [AppSettings]

    // Observed so a theme switch (from `SettingsView`, which writes
    // straight to this singleton) is visible here too — `rootContent`'s
    // `.id(themeManager.theme)` below is what actually forces the
    // re-render, since the six themed `Color` statics are plain computed
    // vars SwiftUI's diffing can't see inside.
    @ObservedObject private var themeManager = ThemeManager.shared

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
                .id(themeManager.theme)
        }
        // `.appTint`, not `.feltGreen`: nav-bar chrome sits directly on the
        // page background, and the dark-page themes (Card Table, Walnut)
        // swap that accent to brass — a deep green control all but vanishes
        // on a felt or walnut page. Re-evaluated on theme change because
        // this view observes `themeManager`.
        .tint(.appTint)
        .preferredColorScheme(preferredColorScheme)
        .onAppear(perform: fireAnnouncerTestIfNeeded)
        .onAppear(perform: loadPersistedTheme)
        .onChange(of: settingsRecords.first?.appTheme) { _, _ in loadPersistedTheme() }
    }

    /// Loads `AppSettings.appTheme` into `ThemeManager.shared` — called on
    /// appear (in case the settings record already exists) and again
    /// whenever the persisted value changes (in case the `@Query` hadn't
    /// loaded it yet on first appear, or it changed some other way).
    /// `SettingsView`'s Theme picker also writes `ThemeManager.shared
    /// .theme` directly on selection, so this is mainly what seeds the
    /// theme at launch.
    private func loadPersistedTheme() {
        if let override = Self.uiTheme {
            themeManager.theme = override
            return
        }
        guard let raw = settingsRecords.first?.appTheme, let theme = AppTheme(rawValue: raw) else { return }
        themeManager.theme = theme
    }

    /// Verification hook for the announcer feature: `-announcerTest`
    /// (combinable with any `-uiScreen`) fires a synthetic three-insight
    /// round-update broadcast one second after launch and prints the
    /// resolved/missing segment counts, so the lead can confirm clip
    /// resolution ran from `simctl` console logs alone — no tapping
    /// required. The third insight is `.freshGame` (empty `playerName`, no
    /// stat clip) so the always-available pregame path's segment
    /// resolution — including the empty-name-slug skip — gets exercised
    /// too, not just the engine-trend kinds.
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
                GameInsights.Insight(
                    icon: "sparkles",
                    text: "Announcer test",
                    priority: 1,
                    kind: .freshGame,
                    playerName: "",
                    value: nil
                ),
            ]
            let segments = AnnouncerPlayer.shared.announceRoundUpdate(insights: insights, voice: .charlie, style: .fun)
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
