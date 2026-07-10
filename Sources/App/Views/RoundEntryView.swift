import SwiftUI
import SwiftData

/// Screens C1/C2 in one view, keyed off `Round.phase`. Creates the round
/// on first appearance if it doesn't exist yet, walks bidding then trick
/// entry, and pops back to `GameView` once the round is complete.
///
/// A round already at `.complete` when this view is pushed (edit entry
/// points from `GameView`'s Rounds section and `ScorepadGridView`'s
/// completed rows, plus `-uiScreen editRound`) instead renders an editable
/// summary — see `EditRoundView` below.
struct RoundEntryView: View {
    @Bindable var game: Game
    let roundNumber: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var round: Round?
    @State private var showMismatchAlert = false
    @State private var mismatchSaveAction: (() -> Void)?
    @State private var showHookAlert = false
    @State private var didConfirm = false
    @State private var hapticsEnabled = true

    var body: some View {
        Group {
            if let round {
                content(for: round)
            } else {
                ProgressView()
            }
        }
        .task {
            ensureRound()
            hapticsEnabled = HapticsGate.isEnabled(in: modelContext)
        }
        .sensoryFeedback(trigger: didConfirm) { _, _ in hapticsEnabled ? .success : nil }
        .alert("Trick Count Mismatch", isPresented: $showMismatchAlert) {
            Button("Fix", role: .cancel) {}
            Button("Save Anyway", role: .destructive) { mismatchSaveAction?() }
        } message: {
            if let round {
                let entered = round.entries.compactMap(\.tricksTaken).reduce(0, +)
                Text("Only \(round.roundNumber) tricks exist this round — you entered \(entered).")
            }
        }
        .alert("Dealer's Hook", isPresented: $showHookAlert) {
            Button("Fix Bids", role: .cancel) {}
        } message: {
            if let round {
                Text("House rule: total bids can't equal \(round.roundNumber). Someone has to be wrong.")
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
            EditRoundView(game: game, round: round, onSave: attemptSaveEdits)
        }
    }

    private func ensureRound() {
        guard round == nil else { return }
        if let existing = game.orderedRounds.first(where: { $0.roundNumber == roundNumber }) {
            round = existing
            return
        }
        // Bids and tricks start untouched (nil), not a pre-seeded 0: the row
        // renders dimmed until the player taps a stepper button, at which
        // point minus explicitly commits 0 and plus commits 1 — a 0 bid is
        // still a single tap. See BiddingView/ResultsView's nil-aware
        // stepper wiring below.
        let entries = game.participants.map { RoundEntry(playerId: $0.playerId, bid: nil, tricksTaken: nil) }
        let dealerId: UUID? = game.rulesSnapshot.dealerRotationEnabled && !game.participants.isEmpty
            ? game.participants[(roundNumber - 1) % game.participants.count].playerId
            : nil
        let newRound = Round(roundNumber: roundNumber, phase: .bidding, entries: entries, dealerPlayerId: dealerId)
        newRound.game = game
        modelContext.insert(newRound)
        game.rounds.append(newRound)
        round = newRound
    }

    /// Gates the "Confirm Bids" transition on the house "Dealer's Hook"
    /// rule: if enabled and every bid is in, a total that exactly equals
    /// the round number blocks the transition with a mandatory-fix alert
    /// rather than proceeding.
    private func confirmBids() {
        guard let round else { return }
        if game.rulesSnapshot.hookRuleEnabled {
            let bids = round.entries.compactMap(\.bid)
            let allIn = bids.count == round.entries.count
            let total = bids.reduce(0, +)
            if allIn && total == round.roundNumber {
                showHookAlert = true
                return
            }
        }
        round.phase = .results
    }

    private func attemptConfirmRound() {
        guard let round else { return }
        let entered = round.entries.compactMap(\.tricksTaken).reduce(0, +)
        if game.rulesSnapshot.trickTotalCheckEnabled && entered != round.roundNumber {
            mismatchSaveAction = completeRound
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

    /// Same soft trick-total check as `attemptConfirmRound`, but for saving
    /// edits to an already-`.complete` round: the round's phase is already
    /// `.complete` and stays there — no re-entry into `game.complete()`,
    /// since that would incorrectly re-stamp `completedAt`/winners for a
    /// game that may have finished on a *later* round than this one.
    private func attemptSaveEdits() {
        guard let round else { return }
        let entered = round.entries.compactMap(\.tricksTaken).reduce(0, +)
        if game.rulesSnapshot.trickTotalCheckEnabled && entered != round.roundNumber {
            mismatchSaveAction = saveEdits
            showMismatchAlert = true
            return
        }
        saveEdits()
    }

    private func saveEdits() {
        didConfirm.toggle()
        dismiss()
    }
}

/// C1: place bids. One row per player with a `SegmentedStepper`; a bid
/// starts nil ("untouched") and renders dimmed until the player taps minus
/// (commits 0) or plus (commits 1). "Confirm Bids" is disabled until every
/// bid is non-nil.
private struct BiddingView: View {
    @Bindable var game: Game
    @Bindable var round: Round
    let onConfirm: () -> Void

    private var range: ClosedRange<Int> { WizardEngine.validRange(roundNumber: round.roundNumber) }

    /// PRD C1: "Bids so far" is the SUM of entered bids — the informational
    /// signal for an over/under-booked round (never a warning, by rule).
    private var bidTotal: Int { round.entries.compactMap(\.bid).reduce(0, +) }

    /// First not-yet-bid participant in seating order, or nil once every
    /// bid is in.
    private var firstWaitingName: String? {
        for participant in game.participants {
            guard let entry = round.entries.first(where: { $0.playerId == participant.playerId }) else { continue }
            if entry.bid == nil { return participant.displayNameSnapshot }
        }
        return nil
    }

    /// Whether `participant` deals this round — only meaningful (and only
    /// ever `true`) when `dealerRotationEnabled`, per `Round.dealerPlayerId`.
    private func isDealer(_ participant: Participant) -> Bool {
        game.rulesSnapshot.dealerRotationEnabled && round.dealerPlayerId == participant.playerId
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(
                    eyebrow: "Round \(round.roundNumber) of \(game.totalRounds)",
                    title: "Place Bids",
                    subtitle: "Deal \(round.roundNumber) card\(round.roundNumber == 1 ? "" : "s") each"
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("Players") {
                ForEach(game.participants, id: \.playerId) { participant in
                    if let index = round.entries.firstIndex(where: { $0.playerId == participant.playerId }) {
                        let entry = round.entries[index]
                        let untouched = entry.bid == nil
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(participant.displayNameSnapshot)
                                        .font(.system(size: 17.5, weight: .bold))
                                    if isDealer(participant) {
                                        DealerTag()
                                    }
                                }
                                if untouched {
                                    Text("Bidding now")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.indigo)
                                } else {
                                    Text("\(game.runningTotal(for: participant.playerId)) pts")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            SegmentedStepper(
                                displayValue: entry.bid ?? 0,
                                dimmed: untouched,
                                minusEnabled: untouched || entry.bid! > range.lowerBound,
                                plusEnabled: untouched || entry.bid! < range.upperBound,
                                onMinus: {
                                    if untouched {
                                        setBid(range.lowerBound, at: index)
                                    } else {
                                        setBid(max(entry.bid! - 1, range.lowerBound), at: index)
                                    }
                                },
                                onPlus: {
                                    if untouched {
                                        setBid(min(1, range.upperBound), at: index)
                                    } else {
                                        setBid(min(entry.bid! + 1, range.upperBound), at: index)
                                    }
                                }
                            )
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(untouched ? Color.indigo.opacity(0.05) : Color(.secondarySystemGroupedBackground))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                footerText
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                PrimaryActionButton(title: "Confirm Bids", isDisabled: firstWaitingName != nil, action: onConfirm)
            }
            .padding()
            .background(.bar)
        }
    }

    /// "Bids so far: **S**" while any bid is nil (plus "· waiting on
    /// <name>"), or "Bids so far: **S** of N tricks" once every bid is in.
    private var footerText: Text {
        if let waiting = firstWaitingName {
            return Text("Bids so far: ")
                + Text("\(bidTotal)").fontWeight(.bold)
                + Text(" · waiting on \(waiting)")
        } else {
            return Text("Bids so far: ")
                + Text("\(bidTotal)").fontWeight(.bold)
                + Text(" of \(round.roundNumber) tricks")
        }
    }

    private func setBid(_ value: Int, at index: Int) {
        var updated = round.entries
        updated[index].bid = value
        round.entries = updated
    }
}

/// C2: enter tricks taken. A trick count starts nil ("untouched") and
/// renders dimmed with no hit/miss tag until the player taps minus (commits
/// 0) or plus (commits 1). "Confirm Round" is disabled until every trick
/// count is non-nil.
private struct ResultsView: View {
    @Bindable var game: Game
    @Bindable var round: Round
    let onConfirm: () -> Void

    private var range: ClosedRange<Int> { WizardEngine.validRange(roundNumber: round.roundNumber) }

    /// PRD C2: "Tricks entered: k of X" — k is the SUM of tricks taken and X
    /// the number of tricks that exist this round (= the round number).
    private var trickTotal: Int { round.entries.compactMap(\.tricksTaken).reduce(0, +) }

    private var allTricksIn: Bool { round.entries.allSatisfy { $0.tricksTaken != nil } }

    /// Whether `participant` deals this round — only meaningful (and only
    /// ever `true`) when `dealerRotationEnabled`, per `Round.dealerPlayerId`.
    private func isDealer(_ participant: Participant) -> Bool {
        game.rulesSnapshot.dealerRotationEnabled && round.dealerPlayerId == participant.playerId
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(
                    eyebrow: "Round \(round.roundNumber) of \(game.totalRounds)",
                    title: "Enter Tricks",
                    subtitle: "Tricks taken must total \(round.roundNumber)"
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("Players") {
                ForEach(game.participants, id: \.playerId) { participant in
                    if let index = round.entries.firstIndex(where: { $0.playerId == participant.playerId }) {
                        let entry = round.entries[index]
                        let untouched = entry.tricksTaken == nil
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(participant.displayNameSnapshot)
                                        .font(.system(size: 17.5, weight: .bold))
                                    if isDealer(participant) {
                                        DealerTag()
                                    }
                                }
                                Text("Bid \(entry.bid ?? 0)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                if let bid = entry.bid, let tricks = entry.tricksTaken {
                                    let score = WizardEngine.roundScore(bid: bid, tricksTaken: tricks)
                                    let hit = bid == tricks
                                    Text("\(hit ? "Hit" : "Miss") · \(ScoreFormat.delta(score))")
                                        .font(.system(size: 13, weight: .bold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(hit ? Color.green.opacity(0.14) : Color.red.opacity(0.13))
                                        .foregroundStyle(hit ? .green : .red)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                SegmentedStepper(
                                    displayValue: entry.tricksTaken ?? 0,
                                    dimmed: untouched,
                                    minusEnabled: untouched || entry.tricksTaken! > range.lowerBound,
                                    plusEnabled: untouched || entry.tricksTaken! < range.upperBound,
                                    onMinus: {
                                        if untouched {
                                            setTricks(range.lowerBound, at: index)
                                        } else {
                                            setTricks(max(entry.tricksTaken! - 1, range.lowerBound), at: index)
                                        }
                                    },
                                    onPlus: {
                                        if untouched {
                                            setTricks(min(1, range.upperBound), at: index)
                                        } else {
                                            setTricks(min(entry.tricksTaken! + 1, range.upperBound), at: index)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(untouched ? Color.indigo.opacity(0.05) : Color(.secondarySystemGroupedBackground))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                (Text("Tricks entered: ") + Text("\(trickTotal) of \(round.roundNumber)").fontWeight(.bold))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                PrimaryActionButton(title: "Confirm Round", isDisabled: !allTricksIn, action: onConfirm)
            }
            .padding()
            .background(.bar)
        }
    }

    private func setTricks(_ value: Int, at index: Int) {
        var updated = round.entries
        updated[index].tricksTaken = value
        round.entries = updated
    }
}

/// Edit mode for an already-`.complete` round, reached from `GameView`'s
/// Rounds section, `ScorepadGridView`'s completed rows, or
/// `-uiScreen editRound`. One row per player with side-by-side Bid/Took
/// steppers and a live hit/miss tag; "Save Changes" leaves `round.phase`
/// at `.complete` and applies the same trick-total soft check C2 uses.
/// Scores are never written here — every total recomputes automatically
/// from the edited entries via `WizardEngine`, per `Round`'s doc comment.
private struct EditRoundView: View {
    @Bindable var game: Game
    @Bindable var round: Round
    let onSave: () -> Void

    private var range: ClosedRange<Int> { WizardEngine.validRange(roundNumber: round.roundNumber) }

    /// A complete round's entries always have non-nil bid/tricks, but the
    /// model type allows `nil` — treated defensively as 0 here.
    private var trickTotal: Int { round.entries.reduce(0) { $0 + ($1.tricksTaken ?? 0) } }

    private func isDealer(_ participant: Participant) -> Bool {
        game.rulesSnapshot.dealerRotationEnabled && round.dealerPlayerId == participant.playerId
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(
                    eyebrow: "Round \(round.roundNumber) of \(game.totalRounds)",
                    title: "Edit Round",
                    subtitle: "Bids and tricks · deal \(round.roundNumber) card\(round.roundNumber == 1 ? "" : "s")"
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("Players") {
                ForEach(game.participants, id: \.playerId) { participant in
                    if let index = round.entries.firstIndex(where: { $0.playerId == participant.playerId }) {
                        editRow(participant: participant, index: index)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                (Text("Tricks entered: ") + Text("\(trickTotal) of \(round.roundNumber)").fontWeight(.bold))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                PrimaryActionButton(title: "Save Changes", action: onSave)
            }
            .padding()
            .background(.bar)
        }
    }

    private func editRow(participant: Participant, index: Int) -> some View {
        let entry = round.entries[index]
        let bid = entry.bid ?? 0
        let tricks = entry.tricksTaken ?? 0
        let hit = bid == tricks
        let score = WizardEngine.roundScore(bid: bid, tricksTaken: tricks)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text(participant.displayNameSnapshot)
                        .font(.system(size: 17.5, weight: .bold))
                    if isDealer(participant) {
                        DealerTag()
                    }
                }
                Spacer()
                Text("\(hit ? "Hit" : "Miss") · \(ScoreFormat.delta(score))")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(hit ? Color.green.opacity(0.14) : Color.red.opacity(0.13))
                    .foregroundStyle(hit ? .green : .red)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bid")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    SegmentedStepper(
                        displayValue: bid,
                        minusEnabled: bid > range.lowerBound,
                        plusEnabled: bid < range.upperBound,
                        onMinus: { setBid(max(bid - 1, range.lowerBound), at: index) },
                        onPlus: { setBid(min(bid + 1, range.upperBound), at: index) }
                    )
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Took")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    SegmentedStepper(
                        displayValue: tricks,
                        minusEnabled: tricks > range.lowerBound,
                        plusEnabled: tricks < range.upperBound,
                        onMinus: { setTricks(max(tricks - 1, range.lowerBound), at: index) },
                        onPlus: { setTricks(min(tricks + 1, range.upperBound), at: index) }
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    private func setBid(_ value: Int, at index: Int) {
        var updated = round.entries
        updated[index].bid = value
        round.entries = updated
    }

    private func setTricks(_ value: Int, at index: Int) {
        var updated = round.entries
        updated[index].tricksTaken = value
        round.entries = updated
    }
}
