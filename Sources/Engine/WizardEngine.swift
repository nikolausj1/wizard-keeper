import Foundation

/// Pure scoring engine for the Wizard card game (standard rules).
/// UI-independent and persistence-independent; the single source of truth
/// for all score math (PRD §8). Scores are always derived through this
/// engine — never stored — so edits and recomputes can never disagree.
public enum WizardEngine {

    // MARK: - Game structure

    public static let minPlayers = 3
    public static let maxPlayers = 6
    public static let deckSize = 60

    /// Total rounds for a player count (60 ÷ players): 3→20, 4→15, 5→12, 6→10.
    /// Returns nil for player counts outside 3–6.
    public static func totalRounds(playerCount: Int) -> Int? {
        guard (minPlayers...maxPlayers).contains(playerCount) else { return nil }
        return deckSize / playerCount
    }

    /// Cards dealt in a round equals the round number (rounds run 1...R),
    /// so bids and tricks taken are both bounded by the round number.
    public static func validRange(roundNumber: Int) -> ClosedRange<Int> {
        0...max(roundNumber, 0)
    }

    // MARK: - Scoring

    /// Standard Wizard round score.
    /// Hit the bid exactly: 20 + 10 per trick bid. Miss: −10 per trick over or under.
    public static func roundScore(bid: Int, tricksTaken: Int) -> Int {
        bid == tricksTaken ? 20 + 10 * bid : -10 * abs(bid - tricksTaken)
    }

    /// One player's completed (bid, tricks) entries in round order →
    /// their running total after each of those rounds.
    public static func runningTotals(entries: [(bid: Int, tricksTaken: Int)]) -> [Int] {
        var total = 0
        return entries.map { entry in
            total += roundScore(bid: entry.bid, tricksTaken: entry.tricksTaken)
            return total
        }
    }

    // MARK: - Ranking

    /// Standard competition ranking ("1-2-2-4"): tied totals share a placement,
    /// and the next distinct total skips the shared slots.
    /// Input order is preserved (placements[i] belongs to totals[i]).
    public static func placements(totals: [Int]) -> [Int] {
        totals.map { total in 1 + totals.filter { $0 > total }.count }
    }

    /// Indices of the winner(s) — highest total. More than one index means a tie.
    public static func winners(totals: [Int]) -> [Int] {
        guard let best = totals.max() else { return [] }
        return totals.indices.filter { totals[$0] == best }
    }
}
