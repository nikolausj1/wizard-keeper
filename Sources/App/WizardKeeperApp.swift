import SwiftUI
import SwiftData

@main
struct WizardKeeperApp: App {
    private let modelContainer: ModelContainer

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isDemoMidGame = arguments.contains("-demoMidGame")
        let isDemoFinal = arguments.contains("-demoFinal")
        let uiScreen = Self.launchArgumentValue("-uiScreen", in: arguments)
        let isDemo = isDemoMidGame || isDemoFinal || uiScreen != nil

        // Any demo/screenshot launch arg forces an in-memory store so seeded
        // data never pollutes real on-device storage.
        let schema = Schema([Player.self, Game.self, Round.self, AppSettings.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isDemo)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        if isDemo {
            let context = ModelContext(modelContainer)
            if isDemoFinal {
                DemoData.seedFinal(in: context)
            } else if isDemoMidGame {
                DemoData.seedMidGame(in: context)
            } else if uiScreen == "newGame" {
                DemoData.seedPlayersOnly(in: context)
            }
            if uiScreen == "results" {
                DemoData.seedRound8AwaitingTricks(in: context)
            }
            try? context.save()
        }
    }

    /// Reads the value following a launch-argument flag, e.g.
    /// `-uiScreen game` → "game".
    static func launchArgumentValue(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
