import SwiftUI
import SwiftData

/// App root: a single `NavigationStack` rooted at `HomeView`, tinted with
/// the one system accent (indigo) per the Apple Native design direction.
///
/// Sim-verify support: `simctl` can't tap, so a `-uiScreen <name>` launch
/// argument (paired with the `-demo*` seeding args, which force an
/// in-memory store) lets a screenshot land directly on any screen:
/// `newGame`, `game`, `bidding`, `results`, or `final`.
struct RootView: View {
    private static let uiScreen = WizardKeeperApp.launchArgumentValue(
        "-uiScreen", in: ProcessInfo.processInfo.arguments
    )

    var body: some View {
        NavigationStack {
            rootContent
        }
        .tint(.indigo)
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

#Preview {
    RootView()
        .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
