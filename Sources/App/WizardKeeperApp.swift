import SwiftUI
import SwiftData

@main
struct WizardKeeperApp: App {
    private let modelContainer: ModelContainer

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isDemoMidGame = arguments.contains("-demoMidGame")
        let isDemoFinal = arguments.contains("-demoFinal")
        let isDemoHistory = arguments.contains("-demoHistory")
        let isDemoFreshGame = arguments.contains("-demoFreshGame")
        let uiScreen = Self.launchArgumentValue("-uiScreen", in: arguments)
        let isDemo = isDemoMidGame || isDemoFinal || isDemoHistory || isDemoFreshGame || uiScreen != nil

        // Any demo/screenshot launch arg forces an in-memory store so seeded
        // data never pollutes real on-device storage.
        let schema = Schema([Player.self, Game.self, Round.self, AppSettings.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isDemo)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Seed the color theme BEFORE the first frame renders: a theme
        // applied later (RootView.onAppear) repaints via observation, but
        // the very first frame would flash the default palette and List
        // row backgrounds have been seen to miss that repaint. Launch-arg
        // override first (sim screenshots), then the persisted setting.
        if let arg = Self.launchArgumentValue("-uiTheme", in: arguments) {
            switch arg {
            case "parchment": ThemeManager.shared.theme = .parchment
            case "cardTable": ThemeManager.shared.theme = .cardTable
            case "walnut": ThemeManager.shared.theme = .walnut
            default: break
            }
        } else if !isDemo,
                  let settings = try? modelContainer.mainContext.fetch(FetchDescriptor<AppSettings>()).first,
                  let theme = AppTheme(rawValue: settings.appTheme) {
            ThemeManager.shared.theme = theme
        }

        if isDemo {
            let context = ModelContext(modelContainer)
            if isDemoFinal {
                DemoData.seedFinal(in: context)
            } else if isDemoMidGame {
                DemoData.seedMidGame(in: context)
            } else if isDemoHistory {
                DemoData.seedHistory(in: context)
            } else if isDemoFreshGame {
                DemoData.seedFreshGame(in: context)
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

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            // Flush to disk the moment we leave the foreground — a
            // force-quit must never cost the table its rounds.
            if newPhase == .background || newPhase == .inactive {
                modelContainer.mainContext.saveNow()
            }
        }
    }
}
