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
        winnerPlayerIds: [UUID] = []
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

    /// The first round number that has not yet reached `.complete`;
    /// `totalRounds` if every dealt round is complete, or 1 if no rounds
    /// have been created yet.
    var currentRoundNumber: Int {
        let ordered = orderedRounds
        for round in ordered where round.phase != .complete {
            return round.roundNumber
        }
        return ordered.isEmpty ? 1 : totalRounds
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
}
