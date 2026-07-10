import SwiftUI
import SwiftData

@main
struct WizardKeeperApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self])
    }
}
