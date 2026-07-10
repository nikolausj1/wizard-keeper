import SwiftUI
import SwiftData

/// Screens C1/C2 in one view, keyed off `Round.phase`. Creates the round
/// on first appearance if it doesn't exist yet, walks bidding then trick
/// entry, and pops back to `GameView` once the round is complete.
struct RoundEntryView: View {
    @Bindable var game: Game
    let roundNumber: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var round: Round?
    @State private var showMismatchAlert = false
    @State private var didConfirm = false

    var body: some View {
        Group {
            if let round {
                content(for: round)
            } else {
                ProgressView()
            }
        }
        .task { ensureRound() }
        .sensoryFeedback(.success, trigger: didConfirm)
        .alert("Trick Count Mismatch", isPresented: $showMismatchAlert) {
            Button("Fix", role: .cancel) {}
            Button("Save Anyway", role: .destructive) { completeRound() }
        } message: {
            if let round {
                let entered = round.entries.compactMap(\.tricksTaken).reduce(0, +)
                Text("Only \(round.roundNumber) tricks exist this round — you entered \(entered).")
            }
        }
    }

    @ViewBuilder
    private func content(for round: Round) -> some View {
        switch round.phase {
        case .bidding:
            BiddingView(game: game, round: round, onConfirm: confirmBids)
        case .results:
            ResultsView(game: game, round: round, onConfirm: attemptConfirmRound)
        case .complete:
            Color.clear
        }
    }

    private func ensureRound() {
        guard round == nil else { return }
        if let existing = game.orderedRounds.first(where: { $0.roundNumber == roundNumber }) {
            round = existing
            return
        }
        // Bids and tricks start at an explicit 0, not nil: 0-bids are the most
        // common bid in Wizard, so the common case costs zero taps. The C2
        // trick-total check catches under-entry before a round can complete.
        let entries = game.participants.map { RoundEntry(playerId: $0.playerId, bid: 0, tricksTaken: 0) }
        let newRound = Round(roundNumber: roundNumber, phase: .bidding, entries: entries)
        newRound.game = game
        modelContext.insert(newRound)
        game.rounds.append(newRound)
        round = newRound
    }

    private func confirmBids() {
        round?.phase = .results
    }

    private func attemptConfirmRound() {
        guard let round else { return }
        let entered = round.entries.compactMap(\.tricksTaken).reduce(0, +)
        if game.rulesSnapshot.trickTotalCheckEnabled && entered != round.roundNumber {
            showMismatchAlert = true
            return
        }
        completeRound()
    }

    private func completeRound() {
        guard let round else { return }
        round.phase = .complete
        let wasFinalRound = roundNumber == game.totalRounds
        if wasFinalRound {
            game.complete()
        }
        didConfirm.toggle()
        dismiss()
    }
}

/// Shared − [value] + control with 44pt touch targets, used for both bids
/// and tricks taken.
private struct StepperControl: View {
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onChange(max(value - 1, range.lowerBound))
            } label: {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
            }
            .disabled(value <= range.lowerBound)

            Text("\(value)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .frame(minWidth: 26)

            Button {
                onChange(min(value + 1, range.upperBound))
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .disabled(value >= range.upperBound)
        }
        .buttonStyle(.bordered)
        .tint(.indigo)
    }
}

/// C1: place bids. One row per player with a stepper; "Confirm Bids" is
/// disabled until every bid is non-nil.
private struct BiddingView: View {
    @Bindable var game: Game
    @Bindable var round: Round
    let onConfirm: () -> Void

    private var range: ClosedRange<Int> { WizardEngine.validRange(roundNumber: round.roundNumber) }

    /// PRD C1: "Bids: total so far" is the SUM of bids — the informational
    /// signal for an over/under-booked round (never a warning, by rule).
    private var bidTotal: Int { round.entries.compactMap(\.bid).reduce(0, +) }

    var body: some View {
        List {
            Section("Players") {
                ForEach(game.participants, id: \.playerId) { participant in
                    if let index = round.entries.firstIndex(where: { $0.playerId == participant.playerId }) {
                        let entry = round.entries[index]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(participant.displayNameSnapshot)
                                    .font(.body.weight(.semibold))
                                Text("\(game.runningTotal(for: participant.playerId)) pts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StepperControl(value: entry.bid ?? range.lowerBound, range: range) { newValue in
                                setBid(newValue, at: index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Place Bids")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .top) {
            header
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Text("Bids: \(bidTotal) so far")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(action: onConfirm) {
                    Text("Confirm Bids")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
            }
            .padding()
            .background(.bar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Round \(round.roundNumber) of \(game.totalRounds)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text("Deal \(round.roundNumber) card\(round.roundNumber == 1 ? "" : "s") each")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 2)
    }

    private func setBid(_ value: Int, at index: Int) {
        var updated = round.entries
        updated[index].bid = value
        round.entries = updated
    }
}

/// C2: enter tricks taken. Shows a live hit/miss chip once both bid and
/// tricks are known; "Confirm Round" is disabled until every trick count is
/// non-nil.
private struct ResultsView: View {
    @Bindable var game: Game
    @Bindable var round: Round
    let onConfirm: () -> Void

    private var range: ClosedRange<Int> { WizardEngine.validRange(roundNumber: round.roundNumber) }

    /// PRD C2: "Tricks entered: k of X" — k is the SUM of tricks taken and X
    /// the number of tricks that exist this round (= the round number).
    private var trickTotal: Int { round.entries.compactMap(\.tricksTaken).reduce(0, +) }

    var body: some View {
        List {
            Section("Players") {
                ForEach(game.participants, id: \.playerId) { participant in
                    if let index = round.entries.firstIndex(where: { $0.playerId == participant.playerId }) {
                        let entry = round.entries[index]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(participant.displayNameSnapshot)
                                    .font(.body.weight(.semibold))
                                Text("Bid \(entry.bid ?? 0)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                if let bid = entry.bid, let tricks = entry.tricksTaken {
                                    let score = WizardEngine.roundScore(bid: bid, tricksTaken: tricks)
                                    let hit = bid == tricks
                                    Text("\(hit ? "Hit" : "Miss") · \(ScoreFormat.delta(score))")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(hit ? Color.green.opacity(0.14) : Color.red.opacity(0.13))
                                        .foregroundStyle(hit ? .green : .red)
                                        .clipShape(Capsule())
                                }
                                StepperControl(value: entry.tricksTaken ?? range.lowerBound, range: range) { newValue in
                                    setTricks(newValue, at: index)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Enter Tricks")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .top) {
            header
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Text("Tricks entered: \(trickTotal) of \(round.roundNumber)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(action: onConfirm) {
                    Text("Confirm Round")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
            }
            .padding()
            .background(.bar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Round \(round.roundNumber) of \(game.totalRounds)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text("Tricks taken must total \(round.roundNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 2)
    }

    private func setTricks(_ value: Int, at index: Int) {
        var updated = round.entries
        updated[index].tricksTaken = value
        round.entries = updated
    }
}
