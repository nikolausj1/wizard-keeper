import Foundation

/// Compile-time game selection for the WizardKeeper target — the one
/// file that differs per app. See `GameVariant` (Engine) for the shape,
/// and Sources/ConfigOhHell/AppGame.swift for the sibling app.
enum AppGame {
    static let config = GameVariant.wizard
}
