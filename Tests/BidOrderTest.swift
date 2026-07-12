import Foundation
import SwiftData

// Simulates the scorer entering round-1 bids in physical order
// D, N, K, J against app seating [J, K, D, N] (seats 0-3).
let participants = ["Justin", "Kelly", "Dave", "Nan"].enumerated().map { i, n in
    Participant(playerId: UUID(), displayNameSnapshot: n, colorIdSnapshot: i)
}
let game = Game(participants: participants, totalRounds: 15,
                rulesSnapshot: RulesSnapshot(hookRuleEnabled: false, trickTotalCheckEnabled: true, dealerRotationEnabled: false))

var checks = 0, failures = 0
func check(_ name: String, _ got: [Int], _ want: [Int]) {
    checks += 1
    if got != want { failures += 1; print("FAIL: \(name) — got \(got), want \(want)") }
}

// Pre-inference: seating order everywhere.
check("pre-inference r1", game.bidOrder(forRound: 1), [0, 1, 2, 3])
check("pre-inference r2", game.bidOrder(forRound: 2), [0, 1, 2, 3])

// Entry sequence: Dave(2), Nan(3), Kelly(1), Justin(0) — as setBid appends.
for seat in [2, 3, 1, 0] {
    if game.firstBidderSeat == nil { game.firstBidderSeat = seat }
    if !game.bidOrderSeats.contains(seat) { game.bidOrderSeats.append(seat) }
}
assert(game.bidOrderInferenceComplete)

// Round 1 = the entry sequence itself; Justin (last entered) dealt round 1.
check("r1 = entry sequence", game.bidOrder(forRound: 1), [2, 3, 1, 0])
// Round 2 rotates one seat: Nan bids first, Dave deals.
check("r2 rotation", game.bidOrder(forRound: 2), [3, 1, 0, 2])
// Round 3: Kelly first, Nan deals.
check("r3 rotation", game.bidOrder(forRound: 3), [1, 0, 2, 3])
// Round 5 wraps fully back to round 1's order.
check("r5 wraps", game.bidOrder(forRound: 5), [2, 3, 1, 0])
// Partial inference (fresh game, only 2 entries) keeps seating order in r1.
let game2 = Game(participants: participants, totalRounds: 15,
                 rulesSnapshot: RulesSnapshot(hookRuleEnabled: false, trickTotalCheckEnabled: true, dealerRotationEnabled: false))
game2.firstBidderSeat = 2
game2.bidOrderSeats = [2, 3]
check("partial r1 stays legacy/seating rotation", game2.bidOrder(forRound: 1), [2, 3, 0, 1])
if game2.bidOrderInferenceComplete { failures += 1; print("FAIL: partial should not be complete") }
// Mid-game added player (seat 4) appends to the end of the learned order.
let five = participants + [Participant(playerId: UUID(), displayNameSnapshot: "Mae", colorIdSnapshot: 4)]
let game3 = Game(participants: five, totalRounds: 15,
                 rulesSnapshot: RulesSnapshot(hookRuleEnabled: false, trickTotalCheckEnabled: true, dealerRotationEnabled: false))
game3.bidOrderSeats = [2, 3, 1, 0]
check("mid-game join appended", game3.bidOrder(forRound: 6), [2, 3, 1, 0, 4])

print(failures == 0 ? "OK — all \(checks) bid-order checks passed" : "FAILED — \(failures)/\(checks)")
exit(failures == 0 ? 0 : 1)
