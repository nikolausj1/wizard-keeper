import Foundation

/// Compile-time game selection for the OhHellKeeper target — the one
/// file that differs per app. See `GameVariant` (Engine) for the shape,
/// and Sources/ConfigWizard/AppGame.swift for the sibling app.
enum AppGame {
    static let config = GameVariant.ohHell
}
