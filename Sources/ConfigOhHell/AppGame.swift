import Foundation

/// Compile-time game selection for the OhHellKeeper target — the one
/// file that differs per app. See `GameVariant` (Engine) for the shape,
/// and Sources/ConfigWizard/AppGame.swift and Sources/ConfigTrashTalk/
/// AppGame.swift for the sibling apps. OhHellKeeper is a clean, all-ages
/// target — `GameVariant.ohHell` carries `allowsSpicyTier: false`, so
/// Settings never offers the Spicy announcer tier here.
enum AppGame {
    static let config = GameVariant.ohHell
}
