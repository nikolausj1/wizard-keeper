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
        /// `broadcastInsights` kinds — the "standings-first" round broadcast.
        /// Slot 1 (the lead story): `leaderTotal` (round 1, or a static-gap
        /// even round), `leadGrew`/`leadShrank` (gap changed, same leader),
        /// `leadStatic` (gap unchanged, no streak), `onTopStreak` (gap
        /// unchanged, ≥3-round tenure, odd round). `leadChange` (above) is
        /// reused when the leader flips. Slot 3 (rotating third story):
        /// `bottomDeeper`/`bottomClimb`/`bottomStatic`/`basementSince`
        /// (bottom-of-the-table rotation), `tiedAt`/`chase` (tightest-race
        /// rotation), `mover` (biggest single-round gain rotation). Garnish:
        /// `earlyGame`/`lateGame`. `winnerBy` is defined here for the audio
        /// mapping's sake but is only ever constructed by the app layer's
        /// end-of-game story, never by `broadcastInsights`.
        case leaderTotal, leadGrew, leadShrank, leadStatic, chase
        case bottomDeeper, bottomClimb, bottomStatic, tiedAt, mover
        case onTopStreak, basementSince, earlyGame, lateGame, winnerBy
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
        /// The headline number for `broadcastInsights` kinds — semantics
        /// vary by kind (a total, a gap, a round delta); nil when the kind
        /// is explicitly scoreless (e.g. `leadStatic`, `bottomStatic`).
        /// Kept separate from `value` (the pre-existing generic number
        /// field, still populated for these kinds too) so `broadcastInsights`
        /// call sites can follow the PRD's per-kind "score" rules exactly
        /// without disturbing `value`'s existing semantics/consumers.
        public let score: Int?
        /// Second player name — only ever non-empty for `tiedAt`.
        public let playerName2: String

        public init(
            icon: String,
            text: String,
            priority: Int,
            kind: Kind,
            playerName: String,
            value: Int?,
            score: Int? = nil,
            playerName2: String = ""
        ) {
            self.icon = icon
            self.text = text
            self.priority = priority
            self.kind = kind
            self.playerName = playerName
            self.value = value
            self.score = score
            self.playerName2 = playerName2
        }
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

    // MARK: - Broadcast insights (standings-first round commentary)

    /// Ordered "standings-first" broadcast for the round just played:
    /// slot 1 is the lead story, slot 2 the juiciest player-level trend,
    /// slot 3 a third story that rotates by round number, plus an optional
    /// nameless game-phase garnish. Every slot's `text` carries the actual
    /// numbers driving it. Requires at least one completed round (returns
    /// `[]` for round zero — the app's pregame path handles that) and, to
    /// keep "the round just played" well-defined, requires every player's
    /// entries to be aligned to the same round count (a mid-game joiner
    /// with a shorter history returns `[]`, same as `insights()`'s
    /// round-news section silently skipping rather than lying — the app
    /// layer falls back to `insights()` in that case).
    public static func broadcastInsights(players: [PlayerLine], totalRounds: Int) -> [Insight] {
        let roundCount = players.map { $0.entries.count }.max() ?? 0
        guard roundCount >= 1, players.count >= 2,
              players.allSatisfy({ $0.entries.count == roundCount }) else { return [] }
        let R = roundCount

        let totalsR = totals(players, through: R)
        guard let bestR = totalsR.max(), let leaderIdxR = totalsR.firstIndex(of: bestR) else { return [] }

        var slots: [Insight] = []

        // MARK: Slot 1 — the lead story
        let slot1: Insight
        if R == 1 {
            slot1 = Insight(
                icon: "crown.fill",
                text: "\(players[leaderIdxR].name) leads with \(bestR)",
                priority: 0, kind: .leaderTotal, playerName: players[leaderIdxR].name, value: bestR, score: bestR
            )
        } else {
            let totalsPrev = totals(players, through: R - 1)
            let bestPrev = totalsPrev.max() ?? 0
            let leaderIdxPrev = totalsPrev.firstIndex(of: bestPrev) ?? leaderIdxR
            if leaderIdxR != leaderIdxPrev {
                slot1 = Insight(
                    icon: "arrow.up.to.line",
                    text: "\(players[leaderIdxR].name) takes the lead with \(bestR)",
                    priority: 0, kind: .leadChange, playerName: players[leaderIdxR].name, value: bestR, score: bestR
                )
            } else {
                let gapR = leaderGap(totalsR)
                let gapPrev = leaderGap(totalsPrev)
                // Tenure override: the gap moves nearly every round (scores
                // always change by ±10s), so the gap-unchanged branch below
                // almost never fires and a long reign would never get its
                // "N straight rounds on top!" call. Every 4th round, a
                // ≥3-round reign outranks the gap news.
                let ledStreak = consecutiveRoundsLed(players, leaderIndex: leaderIdxR, through: R)
                if ledStreak >= 3, R % 4 == 0 {
                    slot1 = Insight(
                        icon: "medal.fill",
                        text: "\(players[leaderIdxR].name): \(ledStreak) straight rounds on top",
                        priority: 0, kind: .onTopStreak, playerName: players[leaderIdxR].name, value: ledStreak, score: ledStreak
                    )
                } else if gapR > gapPrev {
                    slot1 = Insight(
                        icon: "chart.line.uptrend.xyaxis",
                        text: "\(players[leaderIdxR].name)'s lead grows to \(gapR)",
                        priority: 0, kind: .leadGrew, playerName: players[leaderIdxR].name, value: gapR, score: gapR
                    )
                } else if gapR < gapPrev {
                    slot1 = Insight(
                        icon: "chart.line.downtrend.xyaxis",
                        text: "\(players[leaderIdxR].name)'s lead shrinks to \(gapR)",
                        priority: 0, kind: .leadShrank, playerName: players[leaderIdxR].name, value: gapR, score: gapR
                    )
                } else {
                    let streak = consecutiveRoundsLed(players, leaderIndex: leaderIdxR, through: R)
                    if streak >= 3, R % 2 == 1 {
                        slot1 = Insight(
                            icon: "medal.fill",
                            text: "\(players[leaderIdxR].name): \(streak) straight rounds on top",
                            priority: 0, kind: .onTopStreak, playerName: players[leaderIdxR].name, value: streak, score: streak
                        )
                    } else if R % 2 == 0 {
                        slot1 = Insight(
                            icon: "crown.fill",
                            text: "\(players[leaderIdxR].name) leads with \(bestR)",
                            priority: 0, kind: .leaderTotal, playerName: players[leaderIdxR].name, value: bestR, score: bestR
                        )
                    } else {
                        slot1 = Insight(
                            icon: "minus.circle.fill",
                            text: "\(players[leaderIdxR].name) holds a \(gapR)-point lead",
                            priority: 0, kind: .leadStatic, playerName: players[leaderIdxR].name, value: gapR, score: nil
                        )
                    }
                }
            }
        }
        slots.append(slot1)

        // MARK: Slot 2 — the juice: highest-priority player-trend insight
        // from the existing `insights()` ranking, restricted to the more
        // "colorful" kinds, preferring a player other than slot 1's.
        let juiceKinds: Set<Kind> = [
            .perfect, .hotStreak, .coldStreak, .bigRound, .nosedive,
            .zeroSpecialist, .boldestBidder, .everybodyHit, .carnage,
        ]
        let ranked = insights(players: players, maxCount: players.count + 6, pastTense: false)
            .sorted { ($0.priority, $0.text) < ($1.priority, $1.text) }
        let candidates = ranked.filter { juiceKinds.contains($0.kind) }
        let picked = candidates.first { $0.playerName != slot1.playerName } ?? candidates.first
        var slot2: Insight?
        if let picked {
            switch picked.kind {
            case .bigRound, .nosedive:
                // Enrich: score carries the round's point swing (already
                // computed as `value` — bigRound's gain, nosedive's loss as
                // a positive number).
                slot2 = Insight(
                    icon: picked.icon, text: picked.text, priority: 1, kind: picked.kind,
                    playerName: picked.playerName, value: picked.value, score: picked.value
                )
            default:
                slot2 = Insight(
                    icon: picked.icon, text: picked.text, priority: 1, kind: picked.kind,
                    playerName: picked.playerName, value: picked.value
                )
            }
        }
        if let slot2 { slots.append(slot2) }

        // MARK: Slot 3 — rotates by round number
        var slot3: Insight?
        switch R % 3 {
        case 0:
            slot3 = bottomStory(players: players, totalsR: totalsR, roundNumber: R)
        case 1:
            slot3 = chaseOrTieStory(players: players, totalsR: totalsR, bestR: bestR)
        default:
            if let mv = moverStory(players: players, totalsR: totalsR, roundNumber: R),
               mv.playerName != slot1.playerName, mv.playerName != (slot2?.playerName ?? "") {
                slot3 = mv
            } else {
                slot3 = chaseOrTieStory(players: players, totalsR: totalsR, bestR: bestR)
            }
        }
        // Guard against a slot 3 that's a full duplicate of slot 1 (same
        // kind AND same player) — not reachable given the kind sets are
        // disjoint between slot 1 and slot 3 today, but cheap to guard.
        if let s3 = slot3, s3.kind == slot1.kind, s3.playerName == slot1.playerName {
            slot3 = nil
        }
        if let slot3 { slots.append(slot3) }

        // MARK: Garnish — nameless game-phase flavor, appended last
        if R <= 2 {
            slots.append(Insight(
                icon: "sparkles",
                text: "Early days — round \(R) of \(totalRounds)",
                priority: 3, kind: .earlyGame, playerName: "", value: R
            ))
        } else if totalRounds - R <= 2 {
            let remaining = totalRounds - R
            slots.append(Insight(
                icon: "flag.checkered",
                text: "Final stretch — \(remaining) round\(remaining == 1 ? "" : "s") to go",
                priority: 3, kind: .lateGame, playerName: "", value: remaining
            ))
        }

        return slots
    }

    /// Each player's cumulative total through round `r` (1-indexed,
    /// inclusive), computed from their completed-round entries in order.
    private static func totals(_ players: [PlayerLine], through r: Int) -> [Int] {
        guard r > 0 else { return players.map { _ in 0 } }
        return players.map { player in
            player.entries.prefix(r).reduce(0) { $0 + WizardEngine.roundScore(bid: $1.bid, tricksTaken: $1.tricksTaken) }
        }
    }

    /// Leader's total minus the best total among everyone else (0 when the
    /// lead is shared).
    private static func leaderGap(_ totals: [Int]) -> Int {
        guard let best = totals.max(), let leaderIdx = totals.firstIndex(of: best) else { return 0 }
        let bestOther = totals.enumerated().filter { $0.offset != leaderIdx }.map { $0.element }.max() ?? best
        return best - bestOther
    }

    /// How many consecutive rounds ending at `r` `leaderIndex` has held
    /// sole/tie-broken first place.
    private static func consecutiveRoundsLed(_ players: [PlayerLine], leaderIndex: Int, through r: Int) -> Int {
        var count = 0
        var round = r
        while round >= 1 {
            let t = totals(players, through: round)
            guard let best = t.max(), t.firstIndex(of: best) == leaderIndex else { break }
            count += 1
            round -= 1
        }
        return count
    }

    /// How many consecutive rounds ending at `r` `bottomIndex` has held
    /// sole/tie-broken last place.
    private static func consecutiveRoundsAtBottom(_ players: [PlayerLine], bottomIndex: Int, through r: Int) -> Int {
        var count = 0
        var round = r
        while round >= 1 {
            let t = totals(players, through: round)
            guard let worst = t.min(), t.lastIndex(of: worst) == bottomIndex else { break }
            count += 1
            round -= 1
        }
        return count
    }

    /// Slot 3, R % 3 == 0: the bottom-of-the-table story. Compares the
    /// current bottom player's own total this round vs their own total
    /// after the previous round (i.e. how their round just went), then
    /// falls back to a bottom-stint story when that delta is exactly zero.
    private static func bottomStory(players: [PlayerLine], totalsR: [Int], roundNumber: Int) -> Insight {
        let worstR = totalsR.min() ?? 0
        let bottomIdx = totalsR.lastIndex(of: worstR) ?? 0
        let prevTotal = totals(players, through: roundNumber - 1)[bottomIdx]
        let delta = worstR - prevTotal
        // Tenure override: a bottom total is never literally unchanged
        // round-over-round (scores move in ±10s), so without this the
        // basement-tenure arc would never be heard. On every other bottom
        // visit, a ≥3-round stint outranks the up/down news.
        let stint = consecutiveRoundsAtBottom(players, bottomIndex: bottomIdx, through: roundNumber)
        if stint >= 3, roundNumber % 2 == 0 {
            return Insight(
                icon: "hourglass",
                text: "\(players[bottomIdx].name) has been in last since round \(roundNumber - stint + 1)",
                priority: 2, kind: .basementSince, playerName: players[bottomIdx].name, value: roundNumber - stint + 1
            )
        }
        if delta < 0 {
            return Insight(
                icon: "arrow.down.to.line",
                text: "\(players[bottomIdx].name) sinks to \(worstR) in last",
                priority: 2, kind: .bottomDeeper, playerName: players[bottomIdx].name, value: worstR, score: worstR
            )
        } else if delta > 0 {
            return Insight(
                icon: "arrow.up.forward",
                text: "\(players[bottomIdx].name) claws back to \(worstR)",
                priority: 2, kind: .bottomClimb, playerName: players[bottomIdx].name, value: worstR, score: worstR
            )
        } else {
            let streak = consecutiveRoundsAtBottom(players, bottomIndex: bottomIdx, through: roundNumber)
            if streak >= 3 {
                let startRound = roundNumber - streak + 1
                return Insight(
                    icon: "hourglass",
                    text: "\(players[bottomIdx].name) has been in last since round \(startRound)",
                    priority: 2, kind: .basementSince, playerName: players[bottomIdx].name, value: startRound
                )
            } else {
                return Insight(
                    icon: "tortoise.fill",
                    text: "\(players[bottomIdx].name) is stuck at \(worstR)",
                    priority: 2, kind: .bottomStatic, playerName: players[bottomIdx].name, value: worstR
                )
            }
        }
    }

    /// Slot 3, R % 3 == 1 (and the R % 3 == 2 mover fallback): finds the
    /// smallest gap between adjacent ranks anywhere in the standings. A
    /// zero gap fires `tiedAt` for that pair (better-seated player first);
    /// otherwise falls back to the classic "2nd place chasing the leader"
    /// story (guaranteed to have a strictly positive gap, since any zero
    /// gap anywhere would already have been caught above).
    private static func chaseOrTieStory(players: [PlayerLine], totalsR: [Int], bestR: Int) -> Insight {
        let ranked = totalsR.enumerated().sorted { $0.element > $1.element }
        var smallestGap = Int.max
        var tiePair: (Int, Int)?
        for i in 0..<(ranked.count - 1) {
            let gap = ranked[i].element - ranked[i + 1].element
            if gap < smallestGap {
                smallestGap = gap
                tiePair = (ranked[i].offset, ranked[i + 1].offset)
            }
        }
        if smallestGap == 0, let (a, b) = tiePair {
            let (firstSeat, secondSeat) = a < b ? (a, b) : (b, a)
            return Insight(
                icon: "equal.square.fill",
                text: "\(players[firstSeat].name) & \(players[secondSeat].name) tied at \(totalsR[firstSeat])",
                priority: 2, kind: .tiedAt, playerName: players[firstSeat].name,
                value: totalsR[firstSeat], score: totalsR[firstSeat], playerName2: players[secondSeat].name
            )
        } else {
            let secondIdx = ranked.count >= 2 ? ranked[1].offset : ranked[0].offset
            let gap = bestR - totalsR[secondIdx]
            return Insight(
                icon: "figure.run",
                text: "\(players[secondIdx].name) is \(gap) back in 2nd",
                priority: 2, kind: .chase, playerName: players[secondIdx].name, value: gap, score: gap
            )
        }
    }

    /// Slot 3, R % 3 == 2: the player with the biggest strictly-positive
    /// round delta this round (earliest seat wins ties). Nil if nobody
    /// gained ground this round.
    private static func moverStory(players: [PlayerLine], totalsR: [Int], roundNumber: Int) -> Insight? {
        let totalsPrev = totals(players, through: roundNumber - 1)
        var bestDelta = 0
        var moverIdx: Int?
        for i in 0..<players.count {
            let delta = totalsR[i] - totalsPrev[i]
            if delta > bestDelta {
                bestDelta = delta
                moverIdx = i
            }
        }
        guard let moverIdx else { return nil }
        return Insight(
            icon: "arrow.up.right.square.fill",
            text: "\(players[moverIdx].name) jumps \(bestDelta) this round",
            priority: 2, kind: .mover, playerName: players[moverIdx].name, value: bestDelta, score: bestDelta
        )
    }
}
