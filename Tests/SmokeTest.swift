// Wizard Keeper engine smoke test (PRD §10 Phase 1 exit gate).
// Run via the Build Guide engine-test recipe:
//   xattr -cr Sources && cp Tests/SmokeTest.swift <scratch>/main.swift \
//     && swiftc -O Sources/Engine/*.swift <scratch>/main.swift -o <scratch>/t && <scratch>/t
import Foundation

var checks = 0
var failures = 0

func check<T: Equatable>(_ name: String, _ got: T, _ want: T) {
    checks += 1
    if got != want {
        failures += 1
        print("FAIL: \(name) — got \(got), want \(want)")
    }
}

// MARK: PRD §8 worked examples (locked)
check("bid 2 took 2 → +40", WizardEngine.roundScore(bid: 2, tricksTaken: 2), 40)
check("bid 0 took 0 → +20", WizardEngine.roundScore(bid: 0, tricksTaken: 0), 20)
check("bid 3 took 1 → −20", WizardEngine.roundScore(bid: 3, tricksTaken: 1), -20)
check("bid 1 took 4 → −30", WizardEngine.roundScore(bid: 1, tricksTaken: 4), -30)

// MARK: More scoring cases
check("bid 5 took 5 → +70", WizardEngine.roundScore(bid: 5, tricksTaken: 5), 70)
check("bid 0 took 1 → −10", WizardEngine.roundScore(bid: 0, tricksTaken: 1), -10)
check("bid 0 took 3 → −30", WizardEngine.roundScore(bid: 0, tricksTaken: 3), -30)
check("bid 4 took 0 → −40", WizardEngine.roundScore(bid: 4, tricksTaken: 0), -40)
check("bid 10 took 10 → +120", WizardEngine.roundScore(bid: 10, tricksTaken: 10), 120)
check("bid 20 took 20 → +220 (max round, 3p)", WizardEngine.roundScore(bid: 20, tricksTaken: 20), 220)

// Miss score is symmetric: over by k == under by k
for k in 1...5 {
    check("over by \(k) == under by \(k)",
          WizardEngine.roundScore(bid: 3, tricksTaken: 3 + k),
          WizardEngine.roundScore(bid: 3 + k, tricksTaken: 3))
}

// MARK: Round structure (60 ÷ players)
check("3 players → 20 rounds", WizardEngine.totalRounds(playerCount: 3), 20)
check("4 players → 15 rounds", WizardEngine.totalRounds(playerCount: 4), 15)
check("5 players → 12 rounds", WizardEngine.totalRounds(playerCount: 5), 12)
check("6 players → 10 rounds", WizardEngine.totalRounds(playerCount: 6), 10)
check("2 players → invalid", WizardEngine.totalRounds(playerCount: 2), nil as Int?)
check("7 players → invalid", WizardEngine.totalRounds(playerCount: 7), nil as Int?)
check("0 players → invalid", WizardEngine.totalRounds(playerCount: 0), nil as Int?)

// MARK: Valid ranges (bid/tricks bounded by cards dealt)
check("round 1 range", WizardEngine.validRange(roundNumber: 1), 0...1)
check("round 15 range", WizardEngine.validRange(roundNumber: 15), 0...15)
check("range never invalid", WizardEngine.validRange(roundNumber: 0), 0...0)
check("round 1 disallows bid 2", WizardEngine.validRange(roundNumber: 1).contains(2), false)

// MARK: Running totals
check("empty game → no totals", WizardEngine.runningTotals(entries: []), [Int]())
check("single hit", WizardEngine.runningTotals(entries: [(bid: 1, tricksTaken: 1)]), [30])
// Mixed 5-round line: +20, +30, −10, +50, −20 → 20, 50, 40, 90, 70
check("5-round running line",
      WizardEngine.runningTotals(entries: [
          (bid: 0, tricksTaken: 0),   // +20
          (bid: 1, tricksTaken: 1),   // +30
          (bid: 2, tricksTaken: 3),   // −10
          (bid: 3, tricksTaken: 3),   // +50
          (bid: 0, tricksTaken: 2),   // −20
      ]),
      [20, 50, 40, 90, 70])
// A player can go (and stay) negative
check("negative line",
      WizardEngine.runningTotals(entries: [
          (bid: 1, tricksTaken: 0),   // −10
          (bid: 2, tricksTaken: 0),   // −20
          (bid: 0, tricksTaken: 0),   // +20
      ]),
      [-10, -30, -10])

// MARK: Placements (standard competition ranking, ties share)
check("distinct totals", WizardEngine.placements(totals: [120, 80, 150, -20]), [2, 3, 1, 4])
check("two-way tie for first", WizardEngine.placements(totals: [100, 100, 80]), [1, 1, 3])
check("tie in the middle", WizardEngine.placements(totals: [200, 90, 90, 40]), [1, 2, 2, 4])
check("all tied", WizardEngine.placements(totals: [60, 60, 60]), [1, 1, 1])
check("tie for last", WizardEngine.placements(totals: [50, 10, 10]), [1, 2, 2])
check("negatives rank correctly", WizardEngine.placements(totals: [-10, -40, 0]), [2, 3, 1])

// MARK: Winners (indices; >1 means a tie)
check("single winner", WizardEngine.winners(totals: [120, 80, 150, -20]), [2])
check("tied winners", WizardEngine.winners(totals: [100, 100, 80]), [0, 1])
check("all-negative game still has a winner", WizardEngine.winners(totals: [-10, -40, -20]), [0])
check("no players → no winners", WizardEngine.winners(totals: []), [Int]())

// MARK: Full simulated 4-player game (15 rounds, every score cross-checked)
// Player strategy sim: p0 always hits, p1 always misses by 1, p2 alternates,
// p3 bids 0 and hits on even rounds only.
var totals = [0, 0, 0, 0]
for round in 1...15 {
    let bids   = [min(2, round), 1, round % 2 == 0 ? 1 : 0, 0]
    let tricks = [min(2, round), round >= 2 ? 2 : 0, round % 2 == 0 ? 1 : 1, round % 2 == 0 ? 0 : 1]
    for p in 0..<4 {
        totals[p] += WizardEngine.roundScore(bid: bids[p], tricksTaken: tricks[p])
    }
}
// Hand-computed expectations:
// p0: hits every round: r1 bid1(+30), r2..15 bid2(+40 ×14) = 30 + 560 = 590
check("sim p0 total", totals[0], 590)
// p1: r1 bid1 took0 (−10); r2..15 bid1 took2 (−10 ×14) = −150
check("sim p1 total", totals[1], -150)
// p2: even rounds bid1 took1 (+30 ×7); odd rounds bid0 took1 (−10 ×8) = 210 − 80 = 130
check("sim p2 total", totals[2], 130)
// p3: even rounds bid0 took0 (+20 ×7); odd rounds bid0 took1 (−10 ×8) = 140 − 80 = 60
check("sim p3 total", totals[3], 60)
check("sim placements", WizardEngine.placements(totals: totals), [1, 4, 2, 3])
check("sim winner", WizardEngine.winners(totals: totals), [0])

// MARK: GameInsights (trends/outliers on the scoreboard)
typealias Line = GameInsights.PlayerLine
// Zero rounds → nothing; one round → the leader insight fires
check("insights: 0 rounds → none",
      GameInsights.insights(players: [Line(name: "A", entries: [])]).count, 0)
let oneRound = GameInsights.insights(players: [
    Line(name: "A", entries: [(1, 1)]),   // +30 — leads
    Line(name: "B", entries: [(0, 1)]),   // −10
])
check("insights: leader fires from round 1",
      oneRound.contains { $0.text == "A leads with 30" }, true)
// Leader loses the dedupe to a richer insight about the same player
let richer = GameInsights.insights(players: [
    Line(name: "A", entries: [(0, 0), (1, 1), (2, 2)]),  // perfect AND leading
    Line(name: "B", entries: [(0, 1), (1, 0), (0, 1)]),
])
check("insights: perfect beats leading in dedupe",
      richer.filter { $0.playerName == "A" }.count == 1
      && richer.contains { $0.kind == .perfect && $0.playerName == "A" }, true)
// Two rounds is enough for early signals (gate lowered after game-night
// feedback): a 2-miss cold streak fires at round 2.
check("insights: 2-round cold streak fires",
      GameInsights.insights(players: [Line(name: "N", entries: [(1, 0), (2, 0)])])
          .contains { $0.text == "N has missed 2 in a row" }, true)
// Perfect so far
let perfect = GameInsights.insights(players: [
    Line(name: "Kelly", entries: [(0, 0), (1, 1), (2, 2), (0, 0)]),
    Line(name: "Nan", entries: [(0, 1), (1, 0), (0, 0), (1, 1)]),
])
check("insights: perfect detected", perfect.contains { $0.text == "Kelly has hit every bid (4 for 4)" }, true)
// Hot streak (not perfect): miss then 3 hits
let hot = GameInsights.insights(players: [Line(name: "J", entries: [(1, 0), (0, 0), (1, 1), (2, 2)])])
check("insights: hot streak", hot.contains { $0.text == "J is on a 3-hit streak" }, true)
// Cold streak: trailing misses
let cold = GameInsights.insights(players: [Line(name: "N", entries: [(0, 0), (1, 0), (2, 0), (1, 3)])])
check("insights: cold streak", cold.contains { $0.text == "N has missed 3 in a row" }, true)
// Zero specialist
let zero = GameInsights.insights(players: [Line(name: "Z", entries: [(0, 0), (0, 0), (1, 0), (0, 0)])])
check("insights: zero specialist", zero.contains { $0.text == "Z has landed 3 zero bids" }, true)
// Big round: bid 4 hit in round 2 → +60 (no competing streaks on K:
// only one trailing miss, so big round is K's most interesting insight)
let big = GameInsights.insights(players: [
    Line(name: "K", entries: [(0, 1), (4, 4), (1, 1), (0, 1)]),
    Line(name: "B", entries: [(0, 0), (0, 0), (1, 1), (0, 0)]),
])
check("insights: big round", big.contains { $0.text == "K's +60 in round 2 is the round of the game" }, true)
// Dedupe: perfect player also has big round → only one insight for them, the perfect one
let dedupe = GameInsights.insights(players: [
    Line(name: "K", entries: [(4, 4), (0, 0), (1, 1)]),
    Line(name: "B", entries: [(0, 1), (1, 0), (0, 1)]),
])
check("insights: dedupe keeps highest",
      dedupe.filter { $0.text.hasPrefix("K") }.count, 1)
check("insights: dedupe kept perfect",
      dedupe.contains { $0.text == "K has hit every bid (3 for 3)" }, true)
// Max count respected
let capped = GameInsights.insights(players: [
    Line(name: "A", entries: [(0, 0), (0, 0), (0, 0), (0, 0)]),
    Line(name: "B", entries: [(1, 1), (1, 1), (1, 1), (1, 1)]),
    Line(name: "C", entries: [(2, 2), (2, 2), (2, 2), (2, 2)]),
    Line(name: "D", entries: [(0, 0), (1, 1), (0, 0), (1, 1)]),
], maxCount: 3)
check("insights: capped at 3", capped.count, 3)

// MARK: Result
if failures == 0 {
    print("OK — all \(checks) checks passed")
    exit(0)
} else {
    print("FAILED — \(failures) of \(checks) checks failed")
    exit(1)
}
