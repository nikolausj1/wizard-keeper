import Foundation
import SwiftData

/// The app's display appearance preference.
enum Appearance: String, Codable {
    case system
    case light
    case dark
}

/// App-wide user preferences and default rule toggles.
///
/// Invariant: exactly one `AppSettings` record exists in the store at any
/// time. Always obtain it via `fetchOrCreate(in:)` rather than
/// constructing and inserting instances directly, so the singleton
/// invariant can never be violated.
@Model
final class AppSettings {
    /// Default for whether the "hook" scoring rule is enabled on new games.
    var hookRuleEnabled: Bool

    /// Default for whether the trick-total sanity check is enabled on new
    /// games.
    var trickTotalCheckEnabled: Bool

    /// Default for whether the dealer seat rotates automatically each
    /// round.
    var dealerRotationEnabled: Bool

    /// When `true`, new games use the full round count for the seated
    /// player count, via the compiled-in variant's
    /// `AppGame.config.schedule(playerCount:upAndDown:)`. When `false`,
    /// `customRoundCount` supplies the round count instead.
    var useFullLength: Bool

    /// The round count to use for new games when `useFullLength == false`.
    /// Ignored (and expected to be `nil`) when `useFullLength == true`.
    var customRoundCount: Int?

    /// Whether haptic feedback is enabled app-wide.
    var hapticsEnabled: Bool

    /// Backing storage for `appearance`.
    private var appearanceRaw: String

    /// The app's display appearance preference.
    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    /// Backing storage for the announcer's selected voice pack — raw
    /// `AnnouncerVoice.rawValue` ("charlie" / "jessica"). The `AnnouncerVoice`
    /// enum itself lives in the App layer (`Sources/App/Announcer.swift`),
    /// not here, so this Models-layer file stays UI-free; App-layer code
    /// maps this raw string through that enum.
    var announcerVoiceRaw: String = "charlie"

    /// Backing storage for the announcer's selected commentary intensity —
    /// raw `AnnouncerStyle.rawValue` (1...5). See `AnnouncerStyle` in the
    /// App layer for the mapping; styles 4-5 are adults-only.
    var announcerStyle: Int = 1

    /// Backing storage for the selected color theme — raw `AppTheme
    /// .rawValue` (1 Parchment, 2 Card Table, 3 Walnut). The `AppTheme`
    /// enum lives in the App layer (`Sources/App/Theme.swift`), not here,
    /// so this Models-layer file stays UI-free; App-layer code maps this
    /// raw value through that enum. Additive field — defaults to 1
    /// (Parchment) so existing stores migrate to the current look
    /// unchanged.
    var appTheme: Int = 1

    /// Default for the Oh Hell house option: a missed bid still scores 1
    /// point per trick taken (true) vs. zero on any miss (false). Ignored
    /// by Wizard's scoring. Additive field: defaults to true so existing
    /// stores migrate unchanged.
    var missScoresTricks: Bool = true

    /// Default for the Oh Hell house option: up-AND-down deal schedule
    /// (1...max...1, true) vs. up-only like Wizard (false). Ignored by
    /// Wizard. Additive field: defaults to true so existing stores
    /// migrate unchanged.
    var upAndDownSchedule: Bool = true

    init(
        hookRuleEnabled: Bool = false,
        trickTotalCheckEnabled: Bool = true,
        dealerRotationEnabled: Bool = false,
        useFullLength: Bool = true,
        customRoundCount: Int? = nil,
        hapticsEnabled: Bool = true,
        appearance: Appearance = .system,
        announcerVoiceRaw: String = "charlie",
        announcerStyle: Int = 1,
        appTheme: Int = 1,
        missScoresTricks: Bool = true,
        upAndDownSchedule: Bool = true
    ) {
        self.hookRuleEnabled = hookRuleEnabled
        self.trickTotalCheckEnabled = trickTotalCheckEnabled
        self.dealerRotationEnabled = dealerRotationEnabled
        self.useFullLength = useFullLength
        self.customRoundCount = customRoundCount
        self.hapticsEnabled = hapticsEnabled
        self.appearanceRaw = appearance.rawValue
        self.announcerVoiceRaw = announcerVoiceRaw
        self.announcerStyle = announcerStyle
        self.appTheme = appTheme
        self.missScoresTricks = missScoresTricks
        self.upAndDownSchedule = upAndDownSchedule
    }

    /// Fetches the single settings record, creating and inserting one
    /// with default values if none exists yet.
    ///
    /// Invariant: this is the only sanctioned way to obtain an
    /// `AppSettings` instance — it guarantees the store never ends up
    /// with zero or multiple settings records.
    static func fetchOrCreate(in context: ModelContext) throws -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        // New settings records only: seed the "hook" default from the
        // compiled-in variant (Wizard plays it off, Oh Hell's "screw the
        // dealer" plays it on). A store that already has a settings record
        // keeps whatever value it holds, even across an app-target switch.
        let settings = AppSettings(hookRuleEnabled: AppGame.config.hookDefaultOn)
        context.insert(settings)
        return settings
    }

    /// Captures the current rule toggles as a frozen `RulesSnapshot` to
    /// attach to a newly created `Game`.
    func makeRulesSnapshot() -> RulesSnapshot {
        RulesSnapshot(
            hookRuleEnabled: hookRuleEnabled,
            trickTotalCheckEnabled: trickTotalCheckEnabled,
            dealerRotationEnabled: dealerRotationEnabled,
            missScoresTricks: missScoresTricks,
            upAndDownSchedule: upAndDownSchedule
        )
    }
}
