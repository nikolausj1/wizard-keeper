import Foundation

/// Compile-time game selection for the WizardKeeper target — the one
/// file that differs per app. See `GameVariant` (Engine) for the shape,
/// and Sources/ConfigOhHell/AppGame.swift and Sources/ConfigTrashTalk/
/// AppGame.swift for the sibling apps. WizardKeeper is a clean, all-ages
/// target — `GameVariant.wizard` carries `allowsSpicyTier: false`, so
/// Settings never offers the Spicy announcer tier here.
enum AppGame {
    static let config = GameVariant.wizard
}
