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
// Position trio: leader, chaser, and last place fill three lines from round 1
let trio = GameInsights.insights(players: [
    Line(name: "A", entries: [(1, 1)]),   // +30 leads
    Line(name: "B", entries: [(0, 0)]),   // +20 chases (10 behind)
    Line(name: "C", entries: [(0, 1)]),   // −10 last
])
check("insights: three position lines from round 1", trio.count, 3)
check("insights: chaser text", trio.contains { $0.text == "B is 10 behind the lead" }, true)
check("insights: last-place text", trio.contains { $0.text == "C is in last with -10" }, true)
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

// Past-tense mode (Game Story on the final screen)
let story = GameInsights.insights(players: [
    Line(name: "K", entries: [(0, 0), (1, 1), (2, 2)]),
    Line(name: "B", entries: [(0, 1), (1, 0), (2, 0)]),
], pastTense: true)
check("insights: past-tense perfect",
      story.contains { $0.text == "K hit every bid (3 for 3)" }, true)
check("insights: past-tense cold streak",
      story.contains { $0.text == "B ended with 3 misses in a row" }, true)
let storyTrio = GameInsights.insights(players: [
    Line(name: "A", entries: [(1, 1)]),
    Line(name: "B", entries: [(0, 0)]),
    Line(name: "C", entries: [(0, 1)]),
], pastTense: true)
check("insights: past-tense led the field",
      storyTrio.contains { $0.text == "A led the field with 30" }, true)
check("insights: past-tense finished last",
      storyTrio.contains { $0.text == "C finished last with -10" }, true)

// Round-level news
let leadFlip = GameInsights.insights(players: [
    Line(name: "A", entries: [(1, 1), (0, 1)]),   // 30 → 20: led, slipped
    Line(name: "B", entries: [(0, 0), (2, 2)]),   // 20 → 60: takes the lead
    Line(name: "C", entries: [(0, 1), (0, 1)]),
])
check("insights: lead change", leadFlip.contains { $0.text == "B takes the lead" }, true)
let dive = GameInsights.insights(players: [
    Line(name: "A", entries: [(0, 0), (4, 0)]),   // −40 nosedive
    Line(name: "B", entries: [(1, 1), (1, 1)]),
])
check("insights: nosedive", dive.contains { $0.text == "A dropped 40 last round" }, true)
let allHit = GameInsights.insights(players: [
    Line(name: "A", entries: [(1, 1)]), Line(name: "B", entries: [(0, 0)]), Line(name: "C", entries: [(0, 0)]),
])
check("insights: everybody hit", allHit.contains { $0.kind == .everybodyHit }, true)
let bloodbath = GameInsights.insights(players: [
    Line(name: "A", entries: [(1, 0)]), Line(name: "B", entries: [(2, 0)]), Line(name: "C", entries: [(0, 1)]),
])
check("insights: carnage", bloodbath.contains { $0.kind == .carnage }, true)
let photo = GameInsights.insights(players: [
    Line(name: "A", entries: [(1, 1), (1, 1)]),   // 60
    Line(name: "B", entries: [(2, 2), (0, 0)]),   // 60 — dead heat
    Line(name: "C", entries: [(0, 1), (0, 1)]),
], maxCount: 6)  // presence check — don't let the display cap hide it
check("insights: dead heat", photo.contains { $0.text == "Dead heat at the top" }, true)
// Misaligned entry counts (mid-game joiner) → round-news skipped, no crash
let joiner = GameInsights.insights(players: [
    Line(name: "A", entries: [(1, 1), (0, 0)]),
    Line(name: "B", entries: [(0, 0)]),
])
check("insights: joiner skips round news", joiner.contains { $0.kind == .leadChange || $0.kind == .everybodyHit }, false)

// MARK: GameInsights.broadcastInsights (standings-first round broadcast)

// Round 1: no prior round to compare, so slot 1 is a plain leaderTotal.
let bcR1 = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: [(1, 1)]),   // +30
    Line(name: "B", entries: [(0, 1)]),   // −10
], totalRounds: 20)
check("broadcast: leaderTotal fires on round 1",
      bcR1.contains { $0.kind == .leaderTotal && $0.playerName == "A" && $0.score == 30 && $0.text == "A leads with 30" }, true)
check("broadcast: round 1 garnish is earlyGame",
      bcR1.contains { $0.kind == .earlyGame && $0.value == 1 }, true)
check("broadcast: round 1 chase margin",
      bcR1.contains { $0.kind == .chase && $0.playerName == "B" && $0.score == 40 }, true)

// Lead change: slot 1 carries the new leader's total, and — since the
// biggest mover this round IS the new leader — slot 3 falls back from
// mover to the chase/tie rotation instead of duplicating slot 1's player.
let bcLeadChange = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: [(1, 1), (0, 1)]),   // 30 → 20
    Line(name: "B", entries: [(0, 0), (2, 2)]),   // 20 → 60: takes the lead
], totalRounds: 20)
check("broadcast: leadChange carries the new leader's total",
      bcLeadChange.contains { $0.kind == .leadChange && $0.playerName == "B" && $0.score == 60 }, true)
check("broadcast: mover collision with slot 1 falls back to chase",
      bcLeadChange.contains { $0.kind == .chase && $0.playerName == "A" && $0.score == 40 }, true)

// Same leader, growing gap.
let bcLeadGrew = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: [(1, 1), (1, 1)]),   // 30 → 60
    Line(name: "B", entries: [(0, 1), (0, 1)]),   // −10 → −20
], totalRounds: 20)
check("broadcast: leadGrew score is the new gap",
      bcLeadGrew.contains { $0.kind == .leadGrew && $0.playerName == "A" && $0.score == 80 }, true)

// Same leader, shrinking gap.
let bcLeadShrank = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: [(1, 1), (0, 0)]),   // 30 → 50
    Line(name: "B", entries: [(0, 1), (1, 1)]),   // −10 → 20
], totalRounds: 20)
check("broadcast: leadShrank score is the new gap",
      bcLeadShrank.contains { $0.kind == .leadShrank && $0.playerName == "A" && $0.score == 30 }, true)

// Static gap, same leader throughout: an even round falls back to
// leaderTotal, an odd round with ≥3-round tenure fires onTopStreak.
let staticGapEntriesA: [(bid: Int, tricksTaken: Int)] = [(1, 1), (0, 0), (0, 0)]
let staticGapEntriesB: [(bid: Int, tricksTaken: Int)] = [(0, 1), (0, 0), (0, 0)]
let bcStaticEven = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: Array(staticGapEntriesA.prefix(2))),
    Line(name: "B", entries: Array(staticGapEntriesB.prefix(2))),
], totalRounds: 20)
check("broadcast: static gap on an even round is leaderTotal",
      bcStaticEven.contains { $0.kind == .leaderTotal && $0.playerName == "A" && $0.score == 50 }, true)
let bcOnTopStreak = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: staticGapEntriesA),
    Line(name: "B", entries: staticGapEntriesB),
], totalRounds: 20)
check("broadcast: static gap with ≥3-round tenure on an odd round is onTopStreak",
      bcOnTopStreak.contains { $0.kind == .onTopStreak && $0.playerName == "A" && $0.value == 3 && $0.text == "A: 3 straight rounds on top" }, true)

// Static gap, odd round, tenure under 3 rounds → leadStatic (scoreless,
// but the gap is still spelled out in the text).
let bcLeadStatic = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: [(0, 1), (2, 2), (0, 0)]),   // −10 → 30 → 50
    Line(name: "B", entries: [(1, 1), (0, 1), (0, 0)]),   // 30 → 20 → 40
], totalRounds: 20)
check("broadcast: static gap under 3-round tenure on an odd round is leadStatic",
      bcLeadStatic.contains { $0.kind == .leadStatic && $0.playerName == "A" && $0.score == nil && $0.text.contains("10") }, true)

// Bottom rotation (R % 3 == 0): the bottom player's own round-3 delta.
let bcBottomDeeper = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: [(1, 1), (0, 0), (0, 0)]),   // 30 → 50 → 70
    Line(name: "B", entries: [(0, 0), (0, 0), (0, 1)]),   // 20 → 40 → 30
], totalRounds: 20)
check("broadcast: bottomDeeper score is the bottom's new total",
      bcBottomDeeper.contains { $0.kind == .bottomDeeper && $0.playerName == "B" && $0.score == 30 }, true)

let bcBottomClimb = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: [(0, 1), (0, 1), (1, 1)]),   // −10 → −20 → 10
    Line(name: "B", entries: [(0, 0), (1, 1), (0, 0)]),   // 20 → 50 → 70
], totalRounds: 20)
check("broadcast: bottomClimb score is the bottom's new total",
      bcBottomClimb.contains { $0.kind == .bottomClimb && $0.playerName == "A" && $0.score == 10 }, true)

// Tightest-race rotation (R % 3 == 1): an exact tie at round 1.
let bcTied = GameInsights.broadcastInsights(players: [
    Line(name: "C", entries: [(2, 2)]),   // 40 — leads, so the tie below is collision-free
    Line(name: "A", entries: [(1, 1)]),   // 30
    Line(name: "B", entries: [(1, 1)]),   // 30
], totalRounds: 20)
check("broadcast: tiedAt carries both names and the shared total",
      bcTied.contains { $0.kind == .tiedAt && $0.playerName == "A" && $0.playerName2 == "B" && $0.score == 30 }, true)

// Chase margin + lateGame garnish together, round 4 of a 5-round game.
// B is 2nd with no streak of their own (hit-miss-hit-hit), so the juice
// goes to C's cold streak and the chase call survives the no-repeat rule.
let bcChaseAndLate = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: [(2, 2), (2, 2), (2, 2), (2, 2)]),   // 40 → 80 → 120 → 160 — leads
    Line(name: "B", entries: [(1, 1), (1, 0), (1, 1), (1, 1)]),   // 30 → 20 → 50 → 80 — 2nd, quiet
    Line(name: "C", entries: [(0, 1), (0, 1), (0, 1), (0, 1)]),   // −10 each — cold streak
], totalRounds: 5)
check("broadcast: chase margin is the gap to the leader",
      bcChaseAndLate.contains { $0.kind == .chase && $0.playerName == "B" && $0.score == 80 }, true)
check("broadcast: lateGame garnish fires near the end of the game",
      bcChaseAndLate.contains { $0.kind == .lateGame && $0.value == 1 }, true)

// Mover rotation (R % 3 == 2), clear of any slot 1/2 collision.
let bcMover = GameInsights.broadcastInsights(players: [
    Line(name: "A", entries: [(1, 1), (0, 0)]),   // 30 → 50
    Line(name: "B", entries: [(0, 0), (0, 0)]),   // 20 → 40
    Line(name: "C", entries: [(0, 1), (2, 2)]),   // −10 → 30 (+40 this round)
], totalRounds: 20)
check("broadcast: mover score is the round's biggest gain",
      bcMover.contains { $0.kind == .mover && $0.playerName == "C" && $0.score == 40 }, true)

// Slot 2 enrichment: nosedive score is the points lost, as a positive number.
let bcNosedive = GameInsights.broadcastInsights(players: [
    Line(name: "K", entries: [(1, 1), (4, 0)]),   // 30 → −10 (−40 this round)
    Line(name: "B", entries: [(0, 0), (0, 1)]),   // 20 → 10
], totalRounds: 20)
check("broadcast: nosedive score is points lost as a positive number",
      bcNosedive.contains { $0.kind == .nosedive && $0.playerName == "K" && $0.score == 40 }, true)

// Slot 2 enrichment: bigRound score is the round's point gain.
let bcBigRound = GameInsights.broadcastInsights(players: [
    Line(name: "L", entries: [(2, 2), (2, 2), (2, 2)]),   // 40 → 80 → 120 — leads, keeps K juice-eligible
    Line(name: "K", entries: [(0, 1), (4, 4), (1, 1)]),   // −10 → 50 → 80 (+60 round 2)
    Line(name: "B", entries: [(0, 0), (0, 1), (0, 0)]),   // 20 → 10 → 30
], totalRounds: 20)
check("broadcast: bigRound score is the round's point gain",
      bcBigRound.contains { $0.kind == .bigRound && $0.playerName == "K" && $0.score == 60 }, true)

// Tenure override: on a 4th round with a ≥3-round reign, slot 1 is
// onTopStreak even though the gap moved (K leads every round; round 4 is
// R % 4 == 0 and the gap changes round-over-round).
let bcTenureTop = GameInsights.broadcastInsights(players: [
    Line(name: "K", entries: [(2, 2), (2, 2), (2, 2), (2, 2)]),   // 40/80/120/160 — leads all 4
    Line(name: "B", entries: [(0, 0), (0, 1), (0, 0), (0, 1)]),   // 20/10/30/20 — gap keeps moving
], totalRounds: 20)
check("broadcast: 4th-round tenure override yields onTopStreak with reign length",
      bcTenureTop.first?.kind == .onTopStreak && bcTenureTop.first?.value == 4, true)

// Tenure override: bottom slot on an even R%3==0 round (round 6) with a
// ≥3-round basement stint yields basementSince with the stint's start round.
let bcBasement = GameInsights.broadcastInsights(players: [
    Line(name: "K", entries: [(1, 1), (1, 1), (1, 1), (1, 1), (1, 1), (1, 1)]),  // +30 each — top
    Line(name: "M", entries: [(0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0)]),  // +20 each — middle
    Line(name: "N", entries: [(0, 1), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1)]),  // −10 each — bottom all 6
], totalRounds: 20)
check("broadcast: even-round basement tenure yields basementSince from round 1",
      bcBasement.contains { $0.kind == .basementSince && $0.playerName == "N" && $0.value == 1 }, true)

// No player mentioned twice: 2nd place (J) is also the juice (perfect), so
// the R%3==1 race slot would repeat J — it must fall back to the bottom
// story (N), and every named mention across the slots must be unique.
let bcNoRepeat = GameInsights.broadcastInsights(players: [
    Line(name: "K", entries: [(2, 2), (2, 2), (2, 2), (2, 2)]),   // 40/80/120/160 — leads
    Line(name: "J", entries: [(1, 1), (1, 1), (1, 1), (1, 1)]),   // 30/60/90/120 — 2nd, perfect
    Line(name: "N", entries: [(0, 1), (0, 1), (0, 1), (0, 1)]),   // −10 each — bottom
], totalRounds: 20)
var bcMentions: [String] = []
for s in bcNoRepeat {
    if !s.playerName.isEmpty { bcMentions.append(s.playerName) }
    if !s.playerName2.isEmpty { bcMentions.append(s.playerName2) }
}
check("broadcast: no player mentioned twice across slots",
      Set(bcMentions).count == bcMentions.count, true)
check("broadcast: collided race slot falls back to the bottom story",
      bcNoRepeat.contains { $0.playerName == "N" }, true)

// Juice dropped rather than repeating slot 1's player: with 2 players the
// leader (K) owns the only juicy trend (perfect), so slot 2 is omitted and
// slot 3's chase covers the other player.
let bcJuiceDrop = GameInsights.broadcastInsights(players: [
    Line(name: "K", entries: [(1, 1), (1, 1)]),   // 30/60 — leads, perfect
    Line(name: "B", entries: [(0, 1), (0, 0)]),   // −10/10 — mixed, nothing juicy
], totalRounds: 20)
check("broadcast: juice omitted when it would repeat the leader",
      bcJuiceDrop.contains { $0.kind == .perfect }, false)
var bcJDMentions: [String] = []
for s in bcJuiceDrop where !s.playerName.isEmpty { bcJDMentions.append(s.playerName) }
check("broadcast: juice-drop case still mentions each player at most once",
      Set(bcJDMentions).count == bcJDMentions.count, true)

// MARK: Result
if failures == 0 {
    print("OK — all \(checks) checks passed")
    exit(0)
} else {
    print("FAILED — \(failures) of \(checks) checks failed")
    exit(1)
}
