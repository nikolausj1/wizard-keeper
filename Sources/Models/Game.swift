import Foundation
import SwiftData

/// The lifecycle status of a game.
///
/// Invariant: at most one `Game` may be `.inProgress` at any time — see
/// `Game.fetchInProgress`.
enum GameStatus: String, Codable {
    case inProgress
    case completed
}

/// A snapshot of a player's identity at the moment they were seated in a
/// game.
///
/// Invariant: `displayNameSnapshot` and `colorIdSnapshot` are copied from
/// the corresponding `Player` at seating time and never updated
/// afterward. This guarantees that renaming or deleting a `Player` later
/// can never corrupt the historical record of a past game.
struct Participant: Codable {
    var playerId: UUID
    var displayNameSnapshot: String
    var colorIdSnapshot: Int
}

/// A frozen snapshot of the rule toggles in effect when a game began.
///
/// Invariant: changing `AppSettings` after a game has started must never
/// retroactively change the rules that game plays by, so `Game` carries
/// its own copy captured at creation time via
/// `AppSettings.makeRulesSnapshot()`.
struct RulesSnapshot: Codable {
    var hookRuleEnabled: Bool
    var trickTotalCheckEnabled: Bool
    var dealerRotationEnabled: Bool
}

/// A single played (or in-progress) game of Wizard.
///
/// Invariant: scores are never stored on `Game` or `Round` — every total,
/// placement, and winner set is derived at read time from `rounds` via
/// `WizardEngine`, so there is exactly one source of truth for scoring
/// math.
@Model
final class Game {
    /// Stable identity for this game.
    @Attribute(.unique) var id: UUID

    /// When the game was created (first round dealt).
    var createdAt: Date

    /// When the game was marked complete, if it has been.
    var completedAt: Date?

    /// Backing storage for `status`.
    private var statusRaw: String

    /// Seated players, in seating order, carrying identity snapshots so
    /// past games survive player renames/deletions.
    var participants: [Participant]

    /// Total number of rounds this game will play, fixed at creation via
    /// `WizardEngine.totalRounds(playerCount:)` (or a custom override).
    var totalRounds: Int

    /// Frozen copy of the rule toggles in effect when the game began.
    var rulesSnapshot: RulesSnapshot

    /// The rounds played so far. SwiftData does not guarantee array
    /// order — always use `orderedRounds` when order matters. Deleting a
    /// game cascades to delete its rounds.
    @Relationship(deleteRule: .cascade, inverse: \Round.game)
    var rounds: [Round]

    /// Player id(s) who won, set once the game completes. An array to
    /// represent ties.
    var winnerPlayerIds: [UUID]

    /// Seat index (into `participants`) of the round-1 first bidder,
    /// inferred from the first bid interaction; `nil` until observed.
    ///
    /// The scorekeeper doesn't necessarily arrange seating to match deal
    /// order, so this is inferred rather than assumed: Wizard bids start
    /// left of the dealer and the dealer bids last, so whichever seat's
    /// stepper is tapped first in round 1 is the first bidder, and every
    /// later round's first bidder rotates one seat from there. See
    /// `bidOrder(forRound:)`.
    var firstBidderSeat: Int?

    /// The current lifecycle status of this game.
    var status: GameStatus {
        get { GameStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        status: GameStatus = .inProgress,
        participants: [Participant],
        totalRounds: Int,
        rulesSnapshot: RulesSnapshot,
        rounds: [Round] = [],
        winnerPlayerIds: [UUID] = [],
        firstBidderSeat: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.statusRaw = status.rawValue
        self.participants = participants
        self.totalRounds = totalRounds
        self.rulesSnapshot = rulesSnapshot
        self.rounds = rounds
        self.winnerPlayerIds = winnerPlayerIds
        self.firstBidderSeat = firstBidderSeat
    }

    /// Rounds sorted by `roundNumber`. SwiftData relationship arrays have
    /// no guaranteed order, so all callers should read this instead of
    /// `rounds` directly whenever order matters.
    var orderedRounds: [Round] {
        rounds.sorted { $0.roundNumber < $1.roundNumber }
    }

    /// The running total for a single player, summed over all rounds
    /// whose phase is `.complete`. Delegates the per-round math to
    /// `Round.score(for:)`, which itself calls into `WizardEngine`.
    func runningTotal(for playerId: UUID) -> Int {
        orderedRounds.reduce(into: 0) { total, round in
            total += round.score(for: playerId) ?? 0
        }
    }

    /// Running totals for every seated participant, keyed by player id.
    var currentTotals: [UUID: Int] {
        var totals: [UUID: Int] = [:]
        for participant in participants {
            totals[participant.playerId] = runningTotal(for: participant.playerId)
        }
        return totals
    }

    /// The round the table should play next: the first created round that
    /// has not reached `.complete`, otherwise one past the last completed
    /// round (rounds are created lazily), clamped to `totalRounds`.
    var currentRoundNumber: Int {
        let ordered = orderedRounds
        for round in ordered where round.phase != .complete {
            return round.roundNumber
        }
        let next = (ordered.last?.roundNumber ?? 0) + 1
        return min(next, totalRounds)
    }

    /// Seat indices (into `participants`) in bidding order for round `n`.
    ///
    /// Pre-inference (`firstBidderSeat == nil`) this is just seating order —
    /// `Array(participants.indices)` — so screens render top-to-bottom by
    /// seat until a first bid interaction pins down where bidding actually
    /// starts. Once known, the order rotates one seat per round starting
    /// from `firstBidderSeat`, wrapping around the table. The LAST index in
    /// the returned order is that round's dealer (bidding starts left of
    /// the dealer, so the dealer bids last).
    func bidOrder(forRound n: Int) -> [Int] {
        let count = participants.count
        guard let firstBidderSeat, count > 0 else { return Array(participants.indices) }
        let start = (firstBidderSeat + (n - 1)) % count
        return (0..<count).map { (start + $0) % count }
    }

    /// Locates the single in-progress game, if any.
    ///
    /// Invariant: the app never allows more than one `Game` with
    /// `status == .inProgress` to exist simultaneously, so this fetch is
    /// expected to return at most one result. Callers should treat a
    /// second in-progress game found elsewhere as a bug, not a case to
    /// handle.
    static func fetchInProgress(in context: ModelContext) throws -> Game? {
        let inProgressRaw = GameStatus.inProgress.rawValue
        var descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { $0.statusRaw == inProgressRaw }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Marks the game complete: stamps `completedAt`, flips `status`, and
    /// computes `winnerPlayerIds` from the final totals via
    /// `WizardEngine.winners(totals:)`.
    func complete() {
        let orderedParticipants = participants
        let totals = orderedParticipants.map { runningTotal(for: $0.playerId) }
        let winnerIndices = WizardEngine.winners(totals: totals)
        winnerPlayerIds = winnerIndices.compactMap { index in
            orderedParticipants.indices.contains(index) ? orderedParticipants[index].playerId : nil
        }
        completedAt = Date()
        status = .completed
    }

    /// Reopens the most recently completed round for correction: rewinds
    /// its phase from `.complete` back to `.results` so its bids/tricks can
    /// be edited, and — if this game had already finished — reverts
    /// completion too (`status` back to `.inProgress`, `completedAt`
    /// cleared, `winnerPlayerIds` cleared). No-op if no round is
    /// `.complete`.
    ///
    /// Invariant: scores are never stored, only derived from round entries
    /// (see the type-level doc comment), so rewinding a round's phase and
    /// letting its entries be edited is always safe — every downstream
    /// total, standing, and winner recomputes automatically with no risk of
    /// stale cached state.
    func reopenLastCompletedRound() {
        guard let round = orderedRounds.last(where: { $0.phase == .complete }) else { return }
        round.phase = .results
        if status == .completed {
            status = .inProgress
            completedAt = nil
            winnerPlayerIds = []
        }
    }
}
