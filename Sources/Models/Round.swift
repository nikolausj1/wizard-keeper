import Foundation
import SwiftData

/// The lifecycle phase of a single round within a game.
///
/// Invariant: a round only has a well-defined score once it reaches
/// `.complete`. `.bidding` and `.results` are intermediate UI states in
/// which some or all entries may still be missing a bid or trick count.
enum RoundPhase: String, Codable {
    case bidding
    case results
    case complete
}

/// A single participant's bid/tricks record for one round.
///
/// Invariant: `bid` and `tricksTaken` are optional because an entry can
/// exist before a player has locked in a bid or before tricks have been
/// tallied. A score may only be derived once both are non-nil and the
/// owning round's phase is `.complete`.
struct RoundEntry: Codable {
    var playerId: UUID
    var bid: Int?
    var tricksTaken: Int?
}

/// One dealt round of a Wizard game.
///
/// Invariant: scores are never stored on a `RoundEntry` — every score is
/// derived at read time via `WizardEngine.roundScore(bid:tricksTaken:)`,
/// so there is exactly one source of truth for scoring math.
@Model
final class Round {
    /// Number of cards dealt this round. Ranges 1...totalRounds for the
    /// owning game.
    var roundNumber: Int

    /// Backing storage for `phase`.
    private var phaseRaw: String

    /// Per-player bid/tricks data for this round.
    var entries: [RoundEntry]

    /// Inverse of `Game.rounds`.
    var game: Game?

    /// The dealer seat for this round. Only meaningful when the owning
    /// game's `rulesSnapshot.dealerRotationEnabled` is `true`.
    var dealerPlayerId: UUID?

    /// The current lifecycle phase of this round.
    var phase: RoundPhase {
        get { RoundPhase(rawValue: phaseRaw) ?? .bidding }
        set { phaseRaw = newValue.rawValue }
    }

    init(
        roundNumber: Int,
        phase: RoundPhase = .bidding,
        entries: [RoundEntry] = [],
        dealerPlayerId: UUID? = nil
    ) {
        self.roundNumber = roundNumber
        self.phaseRaw = phase.rawValue
        self.entries = entries
        self.dealerPlayerId = dealerPlayerId
    }

    /// Returns the derived score for `playerId`, or `nil` if the round is
    /// not yet `.complete` or the player's bid/tricks aren't both
    /// recorded.
    func score(for playerId: UUID) -> Int? {
        guard phase == .complete else { return nil }
        guard let entry = entries.first(where: { $0.playerId == playerId }) else { return nil }
        guard let bid = entry.bid, let tricksTaken = entry.tricksTaken else { return nil }
        // Scoring routes through the compiled-in game variant (Wizard math
        // in Wizard Keeper, Oh Hell math in Oh Hell Keeper). The miss rule
        // comes from the game's rules snapshot so a Settings change never
        // rewrites an in-progress game.
        let missScoresTricks = game?.rulesSnapshot.missScoresTricks ?? AppGame.config.missScoresTricksDefault
        return AppGame.config.roundScore(bid, tricksTaken, missScoresTricks)
    }

    /// Validates a proposed bid and/or trick count against the legal range
    /// for this round's CARD COUNT (not its round number — the two diverge
    /// on Oh Hell's down-slope), as defined by
    /// `WizardEngine.validRange(roundNumber:)`. A `nil` value is treated
    /// as not-yet-entered and does not fail validation.
    func isValidEntry(bid: Int?, tricksTaken: Int?) -> Bool {
        let cards = game?.cards(forRound: roundNumber) ?? roundNumber
        let range = WizardEngine.validRange(roundNumber: cards)
        if let bid, !range.contains(bid) { return false }
        if let tricksTaken, !range.contains(tricksTaken) { return false }
        return true
    }
}
