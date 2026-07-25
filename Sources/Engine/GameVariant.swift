import Foundation

/// Everything that differs between the three apps built from this codebase
/// — Wizard Keeper, Oh Hell Keeper, and Trash Talk (TrashTalkKeeper, the
/// 18+ target). Each app target compiles in exactly one `AppGame.swift`
/// (see Sources/ConfigWizard / Sources/ConfigOhHell / Sources/
/// ConfigTrashTalk) exposing a `GameVariant` as `AppGame.config`; every
/// shared file reads game-specific behavior through it instead of
/// hardcoding Wizard rules.
///
/// Scoring and schedules are PURE functions living here in the Engine so
/// the swiftc smoke suite covers both variants without an app target.
public struct GameVariant {
    /// Stable variant key: "wizard" | "ohHell" — for the rare UI branch
    /// (e.g. Settings shows Oh Hell's schedule/miss options only there).
    public let id: String

    /// "Wizard Keeper" / "Oh Hell Keeper" — wordmark, recap footer.
    public let displayName: String

    /// Round score for a completed entry. The `RulesSnapshot`-derived flag
    /// is threaded as a plain Bool (`missScoresTricks`) so the engine
    /// stays UI/model-free; Wizard ignores it.
    public let roundScore: (_ bid: Int, _ tricksTaken: Int, _ missScoresTricks: Bool) -> Int

    /// Cards dealt per round, in order, for a player count — the game's
    /// full schedule. Wizard: 1...60÷players. Oh Hell: 1...max...1 (up
    /// AND down; max = 52÷players). `roundNumber` indexes into this
    /// (1-based); it is NOT the card count in Oh Hell's down-slope.
    public let schedule: (_ playerCount: Int, _ upAndDown: Bool) -> [Int]

    /// Default for the "bids can't total the tricks" rule at game
    /// creation. Wizard's table plays it OFF; Oh Hell traditionally plays
    /// it ON ("screw the dealer").
    public let hookDefaultOn: Bool

    /// Whether a missed bid still scores 1 point per trick taken (Oh Hell
    /// house option; Settings-togglable there). Wizard ignores it.
    public let missScoresTricksDefault: Bool

    /// Announcer number-clip family: Wizard scores move in 10s and use the
    /// caster tens library ("One-eighty!" = num_180); Oh Hell scores move
    /// in 1s and use the integer library ("Twenty-three!" = num1_23).
    public let announcerUsesTensClips: Bool

    /// `GameInsights` "big round" gate — a headline-worthy single-round
    /// gain. Wizard: 40+ (a made 2-bid). Oh Hell: 12+ (a made 2-bid).
    public let bigRoundThreshold: Int

    /// Whether this app target may offer the Spicy announcer tier
    /// (`AnnouncerStyle.spicy`, adults-only profanity). `false` for the
    /// two clean, all-ages targets (WizardKeeper, OhHellKeeper) — Spicy is
    /// hidden from Settings and never selectable there, even if a stored
    /// value predates the flag. `true` only for the TrashTalkKeeper target,
    /// which is the sole app that bundles the Spicy clip pack
    /// (`Sources/App/Resources/AnnouncerSpicy/`). Purely a UI/behavior
    /// gate — it does not affect scoring or schedules — but it lives here
    /// alongside the rest of the per-app config so every app-specific
    /// switch is in one place.
    public let allowsSpicyTier: Bool

    public init(
        id: String,
        displayName: String,
        roundScore: @escaping (Int, Int, Bool) -> Int,
        schedule: @escaping (Int, Bool) -> [Int],
        hookDefaultOn: Bool,
        missScoresTricksDefault: Bool,
        announcerUsesTensClips: Bool,
        bigRoundThreshold: Int,
        allowsSpicyTier: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.roundScore = roundScore
        self.schedule = schedule
        self.hookDefaultOn = hookDefaultOn
        self.missScoresTricksDefault = missScoresTricksDefault
        self.announcerUsesTensClips = announcerUsesTensClips
        self.bigRoundThreshold = bigRoundThreshold
        self.allowsSpicyTier = allowsSpicyTier
    }
}

public extension GameVariant {
    /// Standard Wizard (PRD §8, locked): exact bid → 20 + 10×bid;
    /// miss → −10 per trick over or under. Rounds 1...60÷players.
    static let wizard = GameVariant(
        id: "wizard",
        displayName: "Wizard Keeper",
        roundScore: { bid, took, _ in WizardEngine.roundScore(bid: bid, tricksTaken: took) },
        schedule: { players, _ in
            guard let n = WizardEngine.totalRounds(playerCount: players) else { return [] }
            return Array(1...n)
        },
        hookDefaultOn: false,
        missScoresTricksDefault: false,
        announcerUsesTensClips: true,
        bigRoundThreshold: 40,
        allowsSpicyTier: false
    )

    /// Oh Hell, most-common rules (locked with Justin 2026-07-18): exact
    /// bid → 10 + tricks taken; miss → 1 per trick taken (house toggle:
    /// zero on a miss). Up-AND-down schedule 1...max...1, max = 52÷players
    /// (4p: 1–13–1 = 25 rounds). "Screw the dealer" defaults ON.
    static let ohHell = GameVariant(
        id: "ohHell",
        displayName: "Oh Hell Keeper",
        roundScore: { bid, took, missScoresTricks in
            ohHellRoundScore(bid: bid, tricksTaken: took, missScoresTricks: missScoresTricks)
        },
        schedule: { players, upAndDown in
            guard players > 0 else { return [] }
            let maxCards = 52 / players
            guard maxCards >= 1 else { return [] }
            let up = Array(1...maxCards)
            // House option (Settings, snapshotted per game): classic
            // up-AND-down (1...max...1) vs. up-only like Wizard.
            return upAndDown ? up + Array((1..<maxCards).reversed()) : up
        },
        hookDefaultOn: true,
        missScoresTricksDefault: true,
        announcerUsesTensClips: false,
        bigRoundThreshold: 12,
        allowsSpicyTier: false
    )

    /// Oh Hell round scoring, exposed directly for the smoke suite.
    static func ohHellRoundScore(bid: Int, tricksTaken: Int, missScoresTricks: Bool) -> Int {
        if bid == tricksTaken { return 10 + tricksTaken }
        return missScoresTricks ? tricksTaken : 0
    }

    /// Returns a copy of this variant with a different `allowsSpicyTier` —
    /// lets `ConfigTrashTalk` reuse Wizard's game config verbatim (same
    /// scoring, schedule, threshold) while flipping on the 18+ announcer
    /// tier, without duplicating every other field.
    func allowingSpicyTier(_ allowed: Bool) -> GameVariant {
        GameVariant(
            id: id,
            displayName: displayName,
            roundScore: roundScore,
            schedule: schedule,
            hookDefaultOn: hookDefaultOn,
            missScoresTricksDefault: missScoresTricksDefault,
            announcerUsesTensClips: announcerUsesTensClips,
            bigRoundThreshold: bigRoundThreshold,
            allowsSpicyTier: allowed
        )
    }
}
