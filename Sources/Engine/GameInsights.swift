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
    public static let minimumRounds = 3

    /// Ranked insights, at most `maxCount`, at most one per player
    /// (keeping each player's most interesting one).
    public static func insights(players: [PlayerLine], maxCount: Int = 3) -> [Insight] {
        guard let roundCount = players.map({ $0.entries.count }).max(),
              roundCount >= minimumRounds else { return [] }

        var perPlayer: [String: Insight] = [:]

        func offer(_ name: String, _ insight: Insight) {
            if let existing = perPlayer[name], existing.priority <= insight.priority { return }
            perPlayer[name] = insight
        }

        // Big round is cross-player: find the single largest gain (≥ 40).
        var bigRound: (name: String, delta: Int, round: Int)?

        // Boldest bidder is cross-player: strictly highest total bids.
        var bidTotals: [(name: String, total: Int)] = []

        for player in players {
            let entries = player.entries
            guard !entries.isEmpty else { continue }
            let hits = entries.map { $0.bid == $0.tricksTaken }

            // 1. Perfect so far — hit every completed round.
            if hits.allSatisfy({ $0 }) {
                offer(player.name, Insight(
                    icon: "checkmark.seal.fill",
                    text: "\(player.name) has hit every bid (\(entries.count) for \(entries.count))",
                    priority: 0,
                    kind: .perfect, playerName: player.name, value: entries.count
                ))
            } else {
                // 2. Hot streak — trailing consecutive hits ≥ 3.
                let trailingHits = hits.reversed().prefix(while: { $0 }).count
                if trailingHits >= 3 {
                    offer(player.name, Insight(
                        icon: "flame.fill",
                        text: "\(player.name) is on a \(trailingHits)-hit streak",
                        priority: 1,
                        kind: .hotStreak, playerName: player.name, value: trailingHits
                    ))
                }
                // 3. Cold streak — trailing consecutive misses ≥ 2.
                let trailingMisses = hits.reversed().prefix(while: { !$0 }).count
                if trailingMisses >= 2 {
                    offer(player.name, Insight(
                        icon: "snowflake",
                        text: "\(player.name) has missed \(trailingMisses) in a row",
                        priority: 2,
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
                    text: "\(player.name) has landed \(zeroHits) zero bids",
                    priority: 4,
                    kind: .zeroSpecialist, playerName: player.name, value: zeroHits
                ))
            }

            bidTotals.append((player.name, entries.reduce(0) { $0 + $1.bid }))
        }

        if let bigRound {
            offer(bigRound.name, Insight(
                icon: "bolt.fill",
                text: "\(bigRound.name)'s +\(bigRound.delta) in round \(bigRound.round) is the round of the game",
                priority: 3,
                kind: .bigRound, playerName: bigRound.name, value: bigRound.delta
            ))
        }

        // 6. Boldest bidder — strictly highest bid total, at least one per round on average.
        if bidTotals.count >= 2 {
            let sorted = bidTotals.sorted { $0.total > $1.total }
            if sorted[0].total > sorted[1].total, sorted[0].total >= roundCount {
                offer(sorted[0].name, Insight(
                    icon: "arrow.up.right.circle.fill",
                    text: "\(sorted[0].name) is the boldest bidder (\(sorted[0].total) tricks called)",
                    priority: 5,
                    kind: .boldestBidder, playerName: sorted[0].name, value: nil
                ))
            }
        }

        return perPlayer.values.sorted { ($0.priority, $0.text) < ($1.priority, $1.text) }
            .prefix(maxCount).map { $0 }
    }
}
