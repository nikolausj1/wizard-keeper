import Foundation
import SwiftData

/// Seeds in-memory demo data for sim-screenshot verification, driven by
/// launch arguments (`simctl` can't tap, so screens are reached by seeding
/// state directly — see the Build Guide's launch-arg pattern).
///
/// `-demoMidGame` seeds 4 players and a game with rounds 1–7 complete,
/// landing exact totals (Justin 150, Kelly 180, Dave 90, Nan −10) — the same
/// numbers shown in the Apple Native mockup's Screen D. `-demoFinal` extends
/// the same game through all 15 rounds and marks it complete.
///
/// Whenever either flag is present, `WizardKeeperApp` must use an
/// in-memory `ModelContainer` so this data never touches real storage.
enum DemoData {
    private struct RoundSpec {
        let bids: [Int]
        let tricks: [Int]
    }

    private static let demoPlayerNames = ["Justin", "Kelly", "Dave", "Nan"]

    /// Hand-authored rounds 1–7. Each round's tricks sum to its round
    /// number (Wizard invariant: N cards per player means exactly N tricks
    /// total, regardless of player count). Verified against the engine at
    /// seed time via `assert`.
    private static let midGameRoundSpecs: [RoundSpec] = [
        RoundSpec(bids: [1, 0, 0, 0], tricks: [1, 0, 0, 0]),  // R1 (1 trick): Justin hits bid 1.
        RoundSpec(bids: [0, 0, 0, 1], tricks: [0, 0, 0, 2]),  // R2 (2 tricks): Nan misses by 1.
        RoundSpec(bids: [0, 0, 0, 2], tricks: [0, 0, 0, 3]),  // R3 (3 tricks): Nan misses by 1.
        RoundSpec(bids: [0, 4, 0, 0], tricks: [0, 4, 0, 0]),  // R4 (4 tricks): Kelly hits bid 4.
        RoundSpec(bids: [0, 0, 2, 0], tricks: [0, 0, 5, 0]),  // R5 (5 tricks): Dave misses by 3.
        RoundSpec(bids: [0, 0, 0, 4], tricks: [0, 0, 0, 6]),  // R6 (6 tricks): Nan misses by 2.
        RoundSpec(bids: [0, 0, 0, 4], tricks: [0, 0, 0, 7]),  // R7 (7 tricks): Nan misses by 3.
    ]

    static func seedMidGame(in context: ModelContext) {
        seed(throughRound: 7, completeGame: false, in: context)
    }

    static func seedFinal(in context: ModelContext) {
        // No explicit `throughRound`: seeds every round of the compiled-in
        // variant's schedule (Wizard 15 @ 4p; Oh Hell's up-and-down table
        // is longer — 25 @ 4p), so the completed game always reflects a
        // genuine full game under whichever app this runs in.
        seed(completeGame: true, in: context)
    }

    /// `lastRound` defaults to the compiled-in variant's full schedule
    /// length for the seated table (Wizard 15 @ 4p, Oh Hell 25 @ 4p) —
    /// pass an explicit value to stop partway (`seedMidGame`'s round 7).
    private static func seed(throughRound lastRound: Int? = nil, completeGame: Bool, in context: ModelContext) {
        let players = demoPlayerNames.enumerated().map { index, name in
            Player(name: name, colorId: index)
        }
        players.forEach(context.insert)

        let participants = players.map {
            Participant(playerId: $0.id, displayNameSnapshot: $0.name, colorIdSnapshot: $0.colorId)
        }
        // Schedule-driven, not `WizardEngine.totalRounds`, so this seeds
        // correctly under either compiled-in variant — Oh Hell's up-AND-
        // down table diverges from Wizard's round-number-equals-card-count
        // schedule past the midpoint.
        let schedule = AppGame.config.schedule(participants.count, true)
        guard !schedule.isEmpty else {
            assertionFailure("demo player count must be 3–6")
            return
        }
        let totalRounds = schedule.count
        let rulesSnapshot = RulesSnapshot(
            hookRuleEnabled: false,
            trickTotalCheckEnabled: true,
            dealerRotationEnabled: false
        )
        let game = Game(participants: participants, totalRounds: totalRounds, rulesSnapshot: rulesSnapshot)
        context.insert(game)

        let effectiveLastRound = lastRound ?? totalRounds
        for roundNumber in 1...effectiveLastRound {
            let cards = schedule[roundNumber - 1]
            let spec = roundSpec(for: roundNumber, cards: cards, playerCount: participants.count)
            let range = WizardEngine.validRange(roundNumber: cards)
            assert(spec.tricks.reduce(0, +) == cards, "demo round \(roundNumber) tricks must sum to \(cards)")
            assert(spec.bids.allSatisfy { range.contains($0) }, "demo round \(roundNumber) has an out-of-range bid")
            assert(spec.tricks.allSatisfy { range.contains($0) }, "demo round \(roundNumber) has an out-of-range trick count")

            var entries: [RoundEntry] = []
            for (index, participant) in participants.enumerated() {
                entries.append(RoundEntry(playerId: participant.playerId, bid: spec.bids[index], tricksTaken: spec.tricks[index]))
            }

            let round = Round(roundNumber: roundNumber, phase: .complete, entries: entries)
            round.game = game
            context.insert(round)
            game.rounds.append(round)
        }

        // The mockup-matching totals are Wizard-scoring-specific (computed
        // from the same bid/tricks data via 20+10×bid / miss penalties) and
        // only hold at exactly round 7 under Wizard rules — skip for Oh
        // Hell (different scoring formula, different totals from identical
        // entries) and for -demoFinal (rounds 8+ keep scoring).
        if AppGame.config.id == "wizard" && effectiveLastRound == 7 {
            let totals = participants.map { game.runningTotal(for: $0.playerId) }
            assert(totals[0] == 150, "Justin demo total mismatch: \(totals[0])")
            assert(totals[1] == 180, "Kelly demo total mismatch: \(totals[1])")
            assert(totals[2] == 90, "Dave demo total mismatch: \(totals[2])")
            assert(totals[3] == -10, "Nan demo total mismatch: \(totals[3])")
        }

        if completeGame {
            game.complete()
        }
    }

    /// Rounds 1–7 use the hand-authored specs above (their tricks already
    /// sum to `cards`, since Oh Hell's up-slope matches Wizard's round-
    /// number-equals-card-count schedule through round 13). Rounds 8+
    /// (only reached by `-demoFinal`) rotate a single hitter through the
    /// seats so every round's tricks legally sum to `cards` — the actual
    /// count dealt this round, not the round number (they diverge on Oh
    /// Hell's down-slope).
    private static func roundSpec(for roundNumber: Int, cards: Int, playerCount: Int) -> RoundSpec {
        if roundNumber <= midGameRoundSpecs.count {
            return midGameRoundSpecs[roundNumber - 1]
        }
        var bids = [Int](repeating: 0, count: playerCount)
        var tricks = [Int](repeating: 0, count: playerCount)
        let hitter = (roundNumber - 1) % playerCount
        bids[hitter] = cards
        tricks[hitter] = cards
        return RoundSpec(bids: bids, tricks: tricks)
    }

    /// Seeds the four demo players plus an in-progress game with zero
    /// rounds — used for the "always-available Trends" pregame screenshot
    /// (`-demoFreshGame -uiScreen game`), where `GameView` falls back to
    /// its pregame insights (no engine trend history exists yet).
    static func seedFreshGame(in context: ModelContext) {
        let players = demoPlayerNames.enumerated().map { index, name in
            Player(name: name, colorId: index)
        }
        players.forEach(context.insert)

        let participants = players.map {
            Participant(playerId: $0.id, displayNameSnapshot: $0.name, colorIdSnapshot: $0.colorId)
        }
        // Schedule-driven, not `WizardEngine.totalRounds` — see `seed(...)`.
        let schedule = AppGame.config.schedule(participants.count, true)
        guard !schedule.isEmpty else {
            assertionFailure("demo player count must be 3–6")
            return
        }
        let rulesSnapshot = RulesSnapshot(
            hookRuleEnabled: false,
            trickTotalCheckEnabled: true,
            dealerRotationEnabled: false
        )
        let game = Game(participants: participants, totalRounds: schedule.count, rulesSnapshot: rulesSnapshot)
        context.insert(game)
    }

    /// Seeds just the four demo players (no game) — used for the New Game
    /// setup screenshot.
    static func seedPlayersOnly(in context: ModelContext) {
        demoPlayerNames.enumerated().forEach { index, name in
            context.insert(Player(name: name, colorId: index))
        }
    }

    /// On top of `seedMidGame`, creates round 8 in phase `.results` with the
    /// mockup's exact frame-3 data — bids 2/3/1/2, tricks 2/2/1/3 (sum 8) —
    /// so the C2 screenshot compares one-to-one against the mockup.
    static func seedRound8AwaitingTricks(in context: ModelContext) {
        guard let game = try? Game.fetchInProgress(in: context) else { return }
        let bids = [2, 3, 1, 2]
        let tricks = [2, 2, 1, 3]
        let entries = game.participants.enumerated().map { index, participant in
            RoundEntry(playerId: participant.playerId, bid: bids[index], tricksTaken: tricks[index])
        }
        let round = Round(roundNumber: 8, phase: .results, entries: entries)
        round.game = game
        context.insert(round)
        game.rounds.append(round)
    }

    // MARK: - History / Players / Profile demo data (`-demoHistory`)

    /// Seeds the 4 demo players plus three short, *completed* games for the
    /// History (Screen F), Players (Screen G), and PlayerProfile
    /// screenshots. Each game uses a "one hitter takes every trick and
    /// always hits their bid; everyone else bids/takes 0 (which is also
    /// always a hit)" pattern, so every round's tricks trivially sum to the
    /// round number (verified via `assert`, same discipline as
    /// `seedMidGame`). The hitter seat rotates per game so each of the
    /// three games has a different winner, and one round folds in a
    /// deliberate miss for Kelly so her exact-bid-rate stat isn't a trivial
    /// 100%. Games are stamped `daysAgo` apart (0 / 1 / 3) so History's
    /// newest-first ordering has something to sort.
    static func seedHistory(in context: ModelContext) {
        let players = demoPlayerNames.enumerated().map { index, name in
            Player(name: name, colorId: index)
        }
        players.forEach(context.insert)

        let participants = players.map {
            Participant(playerId: $0.id, displayNameSnapshot: $0.name, colorIdSnapshot: $0.colorId)
        }
        let rulesSnapshot = RulesSnapshot(
            hookRuleEnabled: false,
            trickTotalCheckEnabled: true,
            dealerRotationEnabled: false
        )

        // Most recent first: Kelly wins today, Dave wins yesterday (with a
        // folded-in miss for Kelly), Justin wins 3 days ago.
        seedCompletedHistoryGame(hitterIndex: 1, foldInKellyMiss: false, daysAgo: 0, participants: participants, rulesSnapshot: rulesSnapshot, in: context)
        seedCompletedHistoryGame(hitterIndex: 2, foldInKellyMiss: true, daysAgo: 1, participants: participants, rulesSnapshot: rulesSnapshot, in: context)
        seedCompletedHistoryGame(hitterIndex: 0, foldInKellyMiss: false, daysAgo: 3, participants: participants, rulesSnapshot: rulesSnapshot, in: context)
    }

    /// Kelly is always seat index 1 (see `demoPlayerNames`).
    private static let kellySeatIndex = 1

    private static func seedCompletedHistoryGame(
        hitterIndex: Int,
        foldInKellyMiss: Bool,
        daysAgo: Int,
        participants: [Participant],
        rulesSnapshot: RulesSnapshot,
        in context: ModelContext
    ) {
        let day: TimeInterval = 86_400
        let completedDate = Date().addingTimeInterval(-Double(daysAgo) * day)
        let createdDate = completedDate.addingTimeInterval(-600) // a short play session

        let roundCount = 3
        let game = Game(createdAt: createdDate, participants: participants, totalRounds: roundCount, rulesSnapshot: rulesSnapshot)
        context.insert(game)

        for roundNumber in 1...roundCount {
            // `roundCount` is only 3, so `cards` equals `roundNumber` under
            // both variants' schedules (both start 1, 2, 3, ...) — using
            // `game.cards(forRound:)` here anyway keeps this in step with
            // `Round.isValidEntry`'s card-count invariant rather than
            // round number.
            let cards = game.cards(forRound: roundNumber)
            var bids = [Int](repeating: 0, count: participants.count)
            var tricks = [Int](repeating: 0, count: participants.count)
            bids[hitterIndex] = cards
            tricks[hitterIndex] = cards

            // Fold a deliberate miss into round 2 for Kelly when she isn't
            // this game's hitter: she bids 1 but the hitter still takes
            // every trick, so tricks still legally sum to the cards dealt.
            if foldInKellyMiss, roundNumber == 2, hitterIndex != kellySeatIndex {
                bids[kellySeatIndex] = 1
            }

            let range = WizardEngine.validRange(roundNumber: cards)
            assert(tricks.reduce(0, +) == cards, "demo history round \(roundNumber) tricks must sum to \(cards)")
            assert(bids.allSatisfy { range.contains($0) }, "demo history round \(roundNumber) has an out-of-range bid")
            assert(tricks.allSatisfy { range.contains($0) }, "demo history round \(roundNumber) has an out-of-range trick count")

            var entries: [RoundEntry] = []
            for (index, participant) in participants.enumerated() {
                entries.append(RoundEntry(playerId: participant.playerId, bid: bids[index], tricksTaken: tricks[index]))
            }

            let round = Round(roundNumber: roundNumber, phase: .complete, entries: entries)
            round.game = game
            context.insert(round)
            game.rounds.append(round)
        }

        // `Game.complete()` stamps `completedAt` with the real wall-clock
        // "now" — overwrite it afterward so the three demo games land on
        // the spaced-apart dates the screenshot needs.
        game.complete()
        game.completedAt = completedDate
    }
}
