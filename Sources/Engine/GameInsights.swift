import Foundation

/// Mid-game trends and outliers for the scoreboard ("Kelly has hit every
/// bid", "Nan has missed 3 in a row"). Pure Foundation, unit-tested in the
/// engine smoke test; the UI only formats what this emits.
public enum GameInsights {

    public struct PlayerLine {
        public let name: String
        /// Completed rounds only, in round order.
        public let entries: [(bid: Int, tricksTaken: Int)]

        public init(name: String, entries: [(bid: Int, tricksTaken: Int)]) {
            self.name = name
            self.entries = entries
        }
    }

    /// The category of an insight — the audio announcer keys clip
    /// selection off this, so every case maps to a tail-clip family.
    public enum Kind: String, Equatable {
        case perfect, hotStreak, coldStreak, bigRound, zeroSpecialist, boldestBidder
        /// Position insights — fire from the first completed round, so
        /// Trends always has up to three lines mid-game (leader, chaser,
        /// last place). Richer stories about the same player win the dedupe.
        case leading, chasing, trailing
        /// Round-level news (about the round just played): a change at the
        /// top, the round's biggest collapse, table-wide hit/miss extremes,
        /// and a photo-finish gap. `everybodyHit`/`carnage`/`tightRace`
        /// carry no player name (table-wide) — they dedupe by kind.
        case leadChange, nosedive, everybodyHit, carnage, tightRace
        /// Pregame kinds, constructed by the app layer from game history
        /// (the engine only defines them so audio mapping stays kind-keyed).
        case reigningChamp, freshGame
    }

    public struct Insight: Equatable {
        /// SF Symbol name for the row icon.
        public let icon: String
        public let text: String
        /// Lower is more interesting; used for ordering and dedupe.
        public let priority: Int
        /// Structured fields for the audio announcer: what happened, to
        /// whom, and the headline number (streak length, points, zero
        /// count — nil when the kind has no number, e.g. boldest bidder).
        public let kind: Kind
        public let playerName: String
        public let value: Int?
    }

    /// Minimum completed rounds before any insight is worth showing.
    /// Two, not three: the table noticed the Trends section (and its
    /// Announce button) silently missing early in a 20-round game. From
    /// two rounds, cold streaks, +40 rounds, and bold bids can all fire.
    public static let minimumRounds = 2

    /// Ranked insights, at most `maxCount`, at most one per player
    /// (keeping each player's most interesting one).
    /// `pastTense: true` phrases every line for a finished game ("hit
    /// every bid", "finished last with…") — used by the Game Story on the
    /// final screen and the shared recap card.
    public static func insights(players: [PlayerLine], maxCount: Int = 3, pastTense: Bool = false) -> [Insight] {
        guard let roundCount = players.map({ $0.entries.count }).max(),
              roundCount >= 1 else { return [] }

        var perPlayer: [String: Insight] = [:]

        func offer(_ name: String, _ insight: Insight) {
            // Table-wide insights (no player) dedupe by kind, not name —
            // otherwise every nameless insight would collide on "".
            let key = insight.playerName.isEmpty ? "kind:\(insight.kind.rawValue)" : name
            if let existing = perPlayer[key], existing.priority <= insight.priority { return }
            perPlayer[key] = insight
        }

        // Big round is cross-player: find the single largest gain (≥ 40).
        var bigRound: (name: String, delta: Int, round: Int)?

        // Boldest bidder is cross-player: strictly highest total bids.
        var bidTotals: [(name: String, total: Int)] = []

        for player in players where roundCount >= minimumRounds {
            let entries = player.entries
            guard !entries.isEmpty else { continue }
            let hits = entries.map { $0.bid == $0.tricksTaken }

            // 1. Perfect so far — hit every completed round.
            if hits.allSatisfy({ $0 }) {
                offer(player.name, Insight(
                    icon: "checkmark.seal.fill",
                    text: pastTense ? "\(player.name) hit every bid (\(entries.count) for \(entries.count))" : "\(player.name) has hit every bid (\(entries.count) for \(entries.count))",
                    priority: 1,
                    kind: .perfect, playerName: player.name, value: entries.count
                ))
            } else {
                // 2. Hot streak — trailing consecutive hits ≥ 3.
                let trailingHits = hits.reversed().prefix(while: { $0 }).count
                if trailingHits >= 3 {
                    offer(player.name, Insight(
                        icon: "flame.fill",
                        text: pastTense ? "\(player.name) finished on a \(trailingHits)-hit streak" : "\(player.name) is on a \(trailingHits)-hit streak",
                        priority: 2,
                        kind: .hotStreak, playerName: player.name, value: trailingHits
                    ))
                }
                // 3. Cold streak — trailing consecutive misses ≥ 2.
                let trailingMisses = hits.reversed().prefix(while: { !$0 }).count
                if trailingMisses >= 2 {
                    offer(player.name, Insight(
                        icon: "snowflake",
                        text: pastTense ? "\(player.name) ended with \(trailingMisses) misses in a row" : "\(player.name) has missed \(trailingMisses) in a row",
                        priority: 3,
                        kind: .coldStreak, playerName: player.name, value: trailingMisses
                    ))
                }
            }

            // 4. Big round — largest single-round gain of the game, if ≥ 40.
            for (index, entry) in entries.enumerated() {
                let delta = WizardEngine.roundScore(bid: entry.bid, tricksTaken: entry.tricksTaken)
                if delta >= 40, delta > (bigRound?.delta ?? 0) {
                    bigRound = (player.name, delta, index + 1)
                }
            }

            // 5. Zero specialist — three or more successful zero bids.
            let zeroHits = entries.filter { $0.bid == 0 && $0.tricksTaken == 0 }.count
            if zeroHits >= 3 {
                offer(player.name, Insight(
                    icon: "0.circle.fill",
                    text: pastTense ? "\(player.name) landed \(zeroHits) zero bids" : "\(player.name) has landed \(zeroHits) zero bids",
                    priority: 7,
                    kind: .zeroSpecialist, playerName: player.name, value: zeroHits
                ))
            }

            bidTotals.append((player.name, entries.reduce(0) { $0 + $1.bid }))
        }

        if let bigRound {
            offer(bigRound.name, Insight(
                icon: "bolt.fill",
                text: "\(bigRound.name)'s +\(bigRound.delta) in round \(bigRound.round) \(pastTense ? "was" : "is") the round of the game",
                priority: 5,
                kind: .bigRound, playerName: bigRound.name, value: bigRound.delta
            ))
        }

        // 6. Boldest bidder — strictly highest bid total, at least one per round on average.
        if bidTotals.count >= 2 {
            let sorted = bidTotals.sorted { $0.total > $1.total }
            if sorted[0].total > sorted[1].total, sorted[0].total >= roundCount {
                offer(sorted[0].name, Insight(
                    icon: "arrow.up.right.circle.fill",
                    text: "\(sorted[0].name) \(pastTense ? "was" : "is") the boldest bidder (\(sorted[0].total) tricks called)",
                    priority: 8,
                    kind: .boldestBidder, playerName: sorted[0].name, value: nil
                ))
            }
        }

        // Round-level news — what just happened in the latest round. Only
        // computed when every player has an entry for every round (players
        // added mid-game break per-round alignment; skip rather than lie).
        if roundCount >= 1, players.count >= 2,
           players.allSatisfy({ $0.entries.count == roundCount }) {
            let lastScores = players.map { line in
                WizardEngine.roundScore(bid: line.entries[roundCount - 1].bid,
                                        tricksTaken: line.entries[roundCount - 1].tricksTaken)
            }
            let totalsAfter = players.map { line in
                line.entries.reduce(0) { $0 + WizardEngine.roundScore(bid: $1.bid, tricksTaken: $1.tricksTaken) }
            }

            // Lead change: a new name at the top after this round.
            if roundCount >= 2 {
                let totalsBefore = zip(totalsAfter, lastScores).map { $0 - $1 }
                if let bestBefore = totalsBefore.max(), let bestAfter = totalsAfter.max(),
                   let leaderBefore = totalsBefore.firstIndex(of: bestBefore),
                   let leaderAfter = totalsAfter.firstIndex(of: bestAfter),
                   leaderBefore != leaderAfter {
                    offer(players[leaderAfter].name, Insight(
                        icon: "arrow.up.to.line",
                        text: pastTense ? "\(players[leaderAfter].name) took the lead late" : "\(players[leaderAfter].name) takes the lead",
                        priority: 0,
                        kind: .leadChange, playerName: players[leaderAfter].name, value: bestAfter
                    ))
                }
            }

            // Nosedive: the round's biggest collapse (−30 or worse).
            if let worstDrop = lastScores.min(), worstDrop <= -30,
               let dropIndex = lastScores.firstIndex(of: worstDrop) {
                offer(players[dropIndex].name, Insight(
                    icon: "arrow.down.right",
                    text: pastTense ? "\(players[dropIndex].name) dropped \(-worstDrop) in the last round" : "\(players[dropIndex].name) dropped \(-worstDrop) last round",
                    priority: 4,
                    kind: .nosedive, playerName: players[dropIndex].name, value: -worstDrop
                ))
            }

            // Table-wide: everybody hit, or almost nobody did (3+ players).
            if players.count >= 3 {
                let hits = players.enumerated().filter { players[$0.offset].entries[roundCount - 1].bid == players[$0.offset].entries[roundCount - 1].tricksTaken }.count
                if hits == players.count {
                    offer("", Insight(
                        icon: "hands.clap.fill",
                        text: pastTense ? "Everybody hit in round \(roundCount)" : "Everybody hit their bid last round",
                        priority: 6,
                        kind: .everybodyHit, playerName: "", value: nil
                    ))
                } else if hits <= 1 {
                    offer("", Insight(
                        icon: "tornado",
                        text: pastTense ? "\(players.count - hits) of \(players.count) missed in round \(roundCount)" : "\(players.count - hits) of \(players.count) missed last round",
                        priority: 6,
                        kind: .carnage, playerName: "", value: nil
                    ))
                }
            }

            // Tight race: top two within 20 after this round.
            if roundCount >= 2 {
                let sorted = totalsAfter.sorted(by: >)
                if sorted.count >= 2, sorted[0] - sorted[1] <= 20 {
                    let gap = sorted[0] - sorted[1]
                    offer("", Insight(
                        icon: "flag.checkered",
                        text: gap == 0 ? (pastTense ? "It came down to a dead heat at the top" : "Dead heat at the top")
                                       : (pastTense ? "The lead came down to \(gap) points" : "It's a \(gap)-point race at the top"),
                        priority: 9,
                        kind: .tightRace, playerName: "", value: gap
                    ))
                }
            }
        }

        // Position insights — computable from round 1, so Trends (and the
        // announcer) always have up to three lines during a game. Lowest
        // priorities: any richer insight about the same player wins the
        // dedupe, and these fill the remaining slots.
        if players.count >= 2 {
            let totals = players.map { line in
                line.entries.reduce(0) { $0 + WizardEngine.roundScore(bid: $1.bid, tricksTaken: $1.tricksTaken) }
            }
            if let best = totals.max(), let leaderIndex = totals.firstIndex(of: best) {
                offer(players[leaderIndex].name, Insight(
                    icon: "crown.fill",
                    text: pastTense ? "\(players[leaderIndex].name) led the field with \(best)" : "\(players[leaderIndex].name) leads with \(best)",
                    priority: 10,
                    kind: .leading, playerName: players[leaderIndex].name, value: best
                ))

                // Chaser: best total strictly below the lead (first seat wins ties).
                let gaps = totals.enumerated().filter { $0.element < best }
                if let chaser = gaps.max(by: { ($0.element, -$0.offset) < ($1.element, -$1.offset) }) {
                    let gap = best - chaser.element
                    offer(players[chaser.offset].name, Insight(
                        icon: "figure.run",
                        text: pastTense ? "\(players[chaser.offset].name) finished \(gap) behind" : "\(players[chaser.offset].name) is \(gap) behind the lead",
                        priority: 11,
                        kind: .chasing, playerName: players[chaser.offset].name, value: gap
                    ))
                }

                // Last place: strictly the lowest total, when distinct from the lead.
                if let worst = totals.min(), worst < best,
                   let lastIndex = totals.lastIndex(of: worst) {
                    offer(players[lastIndex].name, Insight(
                        icon: "tortoise.fill",
                        text: pastTense ? "\(players[lastIndex].name) finished last with \(worst)" : "\(players[lastIndex].name) is in last with \(worst)",
                        priority: 12,
                        kind: .trailing, playerName: players[lastIndex].name, value: worst
                    ))
                }
            }
        }

        return perPlayer.values.sorted { ($0.priority, $0.text) < ($1.priority, $1.text) }
            .prefix(maxCount).map { $0 }
    }
}
