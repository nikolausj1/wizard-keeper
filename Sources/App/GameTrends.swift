import Foundation
import SwiftData

/// Shared derivation of the Trends section's insights — extracted from
/// `GameView` (its original home) so `ScorepadGridView`'s iPad Trends panel
/// can show the exact same lines instead of leaving the iPad without a
/// Trends section at all. Both views call `displayed(for:in:)` and stay in
/// sync by construction.
enum GameTrends {
    /// What the Trends section actually shows, plus the reigning-champ name
    /// (when there is one) that the round-zero pregame announcer call needs.
    struct Displayed {
        let insights: [GameInsights.Insight]
        /// Only ever non-nil when `insights` is the pregame set (before
        /// round 1's first entry) and a reigning champ is seated at this
        /// table — mirrors `pregameInsights.first { $0.kind == .reigningChamp }`.
        let champName: String?
    }

    /// What the Trends section actually shows: pregame framing before
    /// round 1's first entry, the engine's ranked insights from then on.
    static func displayed(for game: Game, in modelContext: ModelContext) -> Displayed {
        let completedRounds = game.orderedRounds.filter { $0.phase == .complete }
        guard !completedRounds.isEmpty else {
            let pregame = pregameInsights(game: game, in: modelContext)
            let champName = pregame.first { $0.kind == .reigningChamp }?.playerName
            return Displayed(insights: pregame, champName: champName)
        }
        return Displayed(insights: trendInsights(game: game, completedRounds: completedRounds), champName: nil)
    }

    /// Up to 3 ranked mid-game trends/outliers, computed from each
    /// participant's completed-round (bid, tricksTaken) history in seating
    /// order. Non-empty from the first completed round on. Primarily backed
    /// by `GameInsights.broadcastInsights` — the "standings-first" slots
    /// (lead story, juiciest trend, rotating third story, game-phase
    /// garnish) that feed both this Trends UI and the round-update
    /// announcer. Falls back to the older `GameInsights.insights` ranking
    /// when `broadcastInsights` returns nothing (e.g. a mid-game joiner
    /// leaves participants' entry counts misaligned), so Trends is never
    /// silently empty mid-game.
    private static func trendInsights(game: Game, completedRounds: [Round]) -> [GameInsights.Insight] {
        let lines = game.participants.map { participant -> GameInsights.PlayerLine in
            let entries = completedRounds.compactMap { round -> (bid: Int, tricksTaken: Int)? in
                guard let entry = round.entries.first(where: { $0.playerId == participant.playerId }),
                      let bid = entry.bid, let tricksTaken = entry.tricksTaken else { return nil }
                return (bid, tricksTaken)
            }
            return GameInsights.PlayerLine(name: participant.displayNameSnapshot, entries: entries)
        }
        let broadcast = GameInsights.broadcastInsights(players: lines, totalRounds: game.totalRounds)
        if !broadcast.isEmpty { return broadcast }
        return GameInsights.insights(players: lines, maxCount: 3)
    }

    /// Trends before round 1's first entry: not engine-derived (there's no
    /// round history yet), so this is built here from game/table state
    /// instead. Always has at least one line (the "Fresh scorepad" insight
    /// fires unconditionally), so the Trends section never has to be empty
    /// for an in-progress game.
    private static func pregameInsights(game: Game, in modelContext: ModelContext) -> [GameInsights.Insight] {
        var insights: [GameInsights.Insight] = []

        // Fetched once and shared by both the reigning-champ and
        // table-history lines below, rather than each re-querying
        // `modelContext` independently.
        let completed = completedGames(in: modelContext)

        if let lastCompleted = completed.first,
           let winnerId = lastCompleted.winnerPlayerIds.first(where: { id in
               game.participants.contains { $0.playerId == id }
           }),
           let winner = game.participants.first(where: { $0.playerId == winnerId }) {
            insights.append(GameInsights.Insight(
                icon: "crown.fill",
                text: "\(winner.displayNameSnapshot) won the last game",
                priority: 0,
                kind: .reigningChamp,
                playerName: winner.displayNameSnapshot,
                value: nil
            ))
        }

        insights.append(GameInsights.Insight(
            icon: "sparkles",
            text: "Fresh scorepad — \(game.totalRounds) rounds ahead",
            priority: 1,
            kind: .freshGame,
            playerName: "",
            value: nil
        ))

        // Third pregame line: table history, once this table has played at
        // least one completed game before. Deliberately `.freshGame` (not a
        // new kind) so it reuses that kind's audio tails — this is another
        // framing line, not a numeric callout.
        if !completed.isEmpty {
            insights.append(GameInsights.Insight(
                icon: "book.closed.fill",
                text: "Game #\(completed.count + 1) for this table",
                priority: 2,
                kind: .freshGame,
                playerName: "",
                value: nil
            ))
        }

        return insights
    }

    /// Every completed game across the whole history, most recent first —
    /// feeds the reigning-champ and table-history pregame insights above.
    /// `Game.statusRaw` is private to the model, so this fetches everything
    /// and filters/sorts on the public `status` property instead; game
    /// history is small enough for that to be cheap.
    private static func completedGames(in modelContext: ModelContext) -> [Game] {
        let allGames = (try? modelContext.fetch(FetchDescriptor<Game>())) ?? []
        return allGames
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
}
