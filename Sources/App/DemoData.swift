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
        seed(throughRound: 15, completeGame: true, in: context)
    }

    private static func seed(throughRound lastRound: Int, completeGame: Bool, in context: ModelContext) {
        let players = demoPlayerNames.enumerated().map { index, name in
            Player(name: name, colorId: index)
        }
        players.forEach(context.insert)

        let participants = players.map {
            Participant(playerId: $0.id, displayNameSnapshot: $0.name, colorIdSnapshot: $0.colorId)
        }
        guard let totalRounds = WizardEngine.totalRounds(playerCount: participants.count) else {
            assertionFailure("demo player count must be 3–6")
            return
        }
        let rulesSnapshot = RulesSnapshot(
            hookRuleEnabled: false,
            trickTotalCheckEnabled: true,
            dealerRotationEnabled: false
        )
        let game = Game(participants: participants, totalRounds: totalRounds, rulesSnapshot: rulesSnapshot)
        context.insert(game)

        for roundNumber in 1...lastRound {
            let spec = roundSpec(for: roundNumber, playerCount: participants.count)
            let range = WizardEngine.validRange(roundNumber: roundNumber)
            assert(spec.tricks.reduce(0, +) == roundNumber, "demo round \(roundNumber) tricks must sum to \(roundNumber)")
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

        // The mockup-matching totals only hold at exactly round 7 — rounds
        // 8+ keep scoring, so this check must not run for -demoFinal.
        if lastRound == 7 {
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

    /// Rounds 1–7 use the hand-authored specs above. Rounds 8+ (only
    /// reached by `-demoFinal`) rotate a single hitter through the seats so
    /// every round's tricks still legally sum to its round number.
    private static func roundSpec(for roundNumber: Int, playerCount: Int) -> RoundSpec {
        if roundNumber <= midGameRoundSpecs.count {
            return midGameRoundSpecs[roundNumber - 1]
        }
        var bids = [Int](repeating: 0, count: playerCount)
        var tricks = [Int](repeating: 0, count: playerCount)
        let hitter = (roundNumber - 1) % playerCount
        bids[hitter] = roundNumber
        tricks[hitter] = roundNumber
        return RoundSpec(bids: bids, tricks: tricks)
    }

    /// Seeds just the four demo players (no game) — used for the New Game
    /// setup screenshot.
    static func seedPlayersOnly(in context: ModelContext) {
        demoPlayerNames.enumerated().forEach { index, name in
            context.insert(Player(name: name, colorId: index))
        }
    }

    /// On top of `seedMidGame`, creates round 8 with bids locked in
    /// (2+1+3+0 = 6, an under-booked round) and phase `.results` — the C2
    /// "enter tricks" screenshot state.
    static func seedRound8AwaitingTricks(in context: ModelContext) {
        guard let game = try? Game.fetchInProgress(in: context) else { return }
        let bids = [2, 1, 3, 0]
        let entries = zip(game.participants, bids).map {
            RoundEntry(playerId: $0.playerId, bid: $1, tricksTaken: 0)
        }
        let round = Round(roundNumber: 8, phase: .results, entries: entries)
        round.game = game
        context.insert(round)
        game.rounds.append(round)
    }
}
