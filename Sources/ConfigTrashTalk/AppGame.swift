import Foundation

/// Compile-time game selection for the TrashTalkKeeper target — the one
/// file that differs per app. See `GameVariant` (Engine) for the shape,
/// and Sources/ConfigWizard/AppGame.swift and Sources/ConfigOhHell/
/// AppGame.swift for the sibling apps. TrashTalk plays the Wizard game
/// variant (same scoring, schedule, threshold as WizardKeeper) but is the
/// 18+ product — it's the only target that bundles
/// Sources/App/Resources/AnnouncerSpicy/, so it's also the only one that
/// flips `allowsSpicyTier` on, via `allowingSpicyTier(_:)` rather than
/// duplicating `GameVariant.wizard`'s fields.
enum AppGame {
    static let config = GameVariant.wizard.allowingSpicyTier(true)
}
