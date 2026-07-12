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
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var round: Round?
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
        // Enter Tricks sits open for entire hands without a touch — the
        // table's live dashboard must not sleep mid-hand.
        .keepsScreenAwake()
        // Navigation matches the table's mental model (game-night feedback):
        // bids and tricks read as two screens, so back from Enter Tricks
        // returns to Place Bids (bids intact — fix a mis-entered bid on the
        // spot), and back from Place Bids exits to the Scoreboard. Both
        // buttons are labeled so the chevron says where it goes. Edit mode
        // (.complete) keeps the system back — it's reached from several
        // places (Scoreboard, All Rounds).
        .navigationBarBackButtonHidden((round?.phase ?? .complete) != .complete)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let round, round.phase == .bidding {
                    labeledBack("Scoreboard") { dismiss() }
                } else if let round, round.phase == .results {
                    labeledBack("Bids") {
                        round.phase = .bidding
                        modelContext.saveNow()
                    }
                }
            }
        }
        .sensoryFeedback(trigger: didConfirm) { _, _ in hapticsEnabled ? .success : nil }
        .alert("Dealer's Hook", isPresented: $showHookAlert) {
            Button("Fix Bids", role: .cancel) {}
        } message: {
            if let round {
                Text("House rule: total bids can't equal \(round.roundNumber). Someone has to be wrong.")
            }
        }
    }

    /// A system-back-styled labeled button — chevron + destination name.
    private func labeledBack(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                Text(label)
            }
        }
    }

    @ViewBuilder
    private func content(for round: Round) -> some View {
        switch round.phase {
        case .bidding:
            BiddingView(game: game, round: round, onConfirm: confirmBids)
        case .results:
            ResultsView(game: game, round: round, onConfirm: completeRound)
        case .complete:
            EditRoundView(game: game, round: round, onSave: saveEdits)
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
        modelContext.saveNow()
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
        modelContext.saveNow()
    }

    /// The trick-total soft check that used to live behind a save-time
    /// "Trick Count Mismatch" alert here now lives up front as button
    /// gating in `ResultsView`/`EditRoundView` (state-driven "Enter N More
    /// Trick(s)" / "N Too Many" labels via `PrimaryActionButton`'s
    /// `isDisabled`) — `onConfirm`/`onSave` are only ever invoked once the
    /// count already matches (or the house rule is off), so there's
    /// nothing left to gate here.
    private func completeRound() {
        guard let round else { return }
        round.phase = .complete
        let wasFinalRound = roundNumber == game.totalRounds
        if wasFinalRound {
            game.complete()
        }
        modelContext.saveNow()
        didConfirm.toggle()
        dismiss()
    }

    /// Saves edits to an already-`.complete` round: the round's phase is
    /// already `.complete` and stays there — no re-entry into
    /// `game.complete()`, since that would incorrectly re-stamp
    /// `completedAt`/winners for a game that may have finished on a
    /// *later* round than this one. See `completeRound`'s doc comment for
    /// where the trick-total check now lives.
    private func saveEdits() {
        modelContext.saveNow()
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
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var themeManager = ThemeManager.shared
    let onConfirm: () -> Void

    private var range: ClosedRange<Int> { WizardEngine.validRange(roundNumber: round.roundNumber) }

    /// PRD C1: "Bids so far" is the SUM of entered bids — the informational
    /// signal for an over/under-booked round (never a warning, by rule).
    private var bidTotal: Int { round.entries.compactMap(\.bid).reduce(0, +) }

    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 17.5
    @ScaledMetric(relativeTo: .subheadline) private var statusSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var footerSize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .largeTitle) private var footerHeroSize: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var dealSubtitleBaseSize: CGFloat = 17
    @ScaledMetric(relativeTo: .largeTitle) private var dealSubtitleCountSize: CGFloat = 20

    /// Whether every seated participant has a bid in — gates "Confirm
    /// Bids".
    private var allBidsIn: Bool { round.entries.allSatisfy { $0.bid != nil } }

    /// Seat index of the first not-yet-bid participant in BID order (the
    /// actual turn order the table bids in, via `game.bidOrder(forRound:)`
    /// — not raw seating), or nil once every bid is in. This is also the
    /// only row that shows "Bidding now"; every other not-yet-bid row
    /// shows the neutral "No bid yet" instead, so exactly one row ever
    /// claims to be on the clock.
    private var firstWaitingSeatIndex: Int? {
        for seatIndex in game.bidOrder(forRound: round.roundNumber) {
            guard game.participants.indices.contains(seatIndex) else { continue }
            let participant = game.participants[seatIndex]
            guard let entry = round.entries.first(where: { $0.playerId == participant.playerId }) else { continue }
            if entry.bid == nil { return seatIndex }
        }
        return nil
    }

    /// Seat index of this round's dealer once `game.firstBidderSeat`
    /// inference has fired — the last seat in `game.bidOrder(forRound:)`,
    /// since bidding starts left of the dealer. `nil` pre-inference.
    private var dealerSeatIndex: Int? {
        guard game.firstBidderSeat != nil else { return nil }
        return game.bidOrder(forRound: round.roundNumber).last
    }

    /// The dealer's display name for the header subtitle: the inferred
    /// dealer when known, else the old toggle-driven `Round.dealerPlayerId`,
    /// else nil (no dealer concept for this game yet).
    private var currentDealerName: String? {
        if let dealerSeatIndex, game.participants.indices.contains(dealerSeatIndex) {
            return game.participants[dealerSeatIndex].displayNameSnapshot
        }
        // No positional guess before inference — see game-night feedback.
        return nil
    }

    /// Whether `participant` deals this round: the inferred dealer (last
    /// seat in bid order) once `game.firstBidderSeat` is known, otherwise
    /// the old toggle-driven `Round.dealerPlayerId` — never both, so a row
    /// never shows two dealer tags.
    private func isDealer(_ participant: Participant) -> Bool {
        if let dealerSeatIndex {
            guard let seatIndex = game.participants.firstIndex(where: { $0.playerId == participant.playerId }) else { return false }
            return seatIndex == dealerSeatIndex
        }
        return false  // never guess the dealer before round 1's first bid
    }

    /// "Deal **N cards** each" with the count as the hero (20pt heavy),
    /// rendered as a custom line under `ScreenHeader` rather than through
    /// its plain-string `subtitle` so only the count gets the bigger,
    /// heavier treatment. Appends " · <dealer name> deals" once a dealer is
    /// known (inferred or toggle-driven).
    private var dealSubtitleText: Text {
        let n = round.roundNumber
        var text = Text("Deal ")
            .font(.system(size: dealSubtitleBaseSize, weight: .semibold))
            .foregroundStyle(.secondary)
            + Text("\(n)")
            .font(.system(size: dealSubtitleCountSize, weight: .heavy))
            .foregroundStyle(.primary)
            + Text(" card\(n == 1 ? "" : "s") each")
            .font(.system(size: dealSubtitleBaseSize, weight: .semibold))
            .foregroundStyle(.secondary)
        if let currentDealerName {
            text = text + Text(" · \(currentDealerName) deals")
                .font(.system(size: dealSubtitleBaseSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        return text
    }

    /// A bid-tally number rendered as the footer's hero: 20pt heavy
    /// monospaced primary text, standing out against the 14.5pt secondary
    /// label around it.
    private func heroNumber(_ value: Int) -> Text {
        Text("\(value)")
            .font(.system(size: footerHeroSize, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.primary)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    ScreenHeader(
                        eyebrow: "Round \(round.roundNumber) of \(game.totalRounds)",
                        title: "Place Bids",
                        subtitle: nil
                    )
                    dealSubtitleText
                        .padding(.horizontal, 4)
                        // Sibling of `ScreenHeader`, so it doesn't get that
                        // view's own bottom padding — without this the line
                        // sits flush against the zero-inset row's bottom
                        // edge and its leading "D" (rounded overshoot) gets
                        // clipped. See `ScreenHeader`'s matching comment.
                        .padding(.bottom, 4)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                // Rendered in `game.bidOrder(forRound:)` order, not raw
                // seating — once the first bidder is inferred, that seat is
                // always the top row, since the scorer works top to bottom.
                ForEach(game.bidOrder(forRound: round.roundNumber), id: \.self) { seatIndex in
                    if game.participants.indices.contains(seatIndex) {
                        let participant = game.participants[seatIndex]
                        if let index = round.entries.firstIndex(where: { $0.playerId == participant.playerId }) {
                            let entry = round.entries[index]
                            let untouched = entry.bid == nil
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(participant.displayNameSnapshot)
                                            .font(.system(size: nameSize, weight: .bold))
                                        if isDealer(participant) {
                                            DealerTag()
                                        }
                                    }
                                    if untouched {
                                        if seatIndex == firstWaitingSeatIndex {
                                            Text("Bidding now")
                                                .font(.system(size: statusSize, weight: .semibold))
                                                .foregroundStyle(Color.feltGreen)
                                        } else {
                                            Text("No bid yet")
                                                .font(.system(size: statusSize, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Text("\(game.runningTotal(for: participant.playerId)) pts")
                                            .font(.system(size: statusSize, weight: .medium))
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
                                            setBid(range.lowerBound, seatIndex: seatIndex, at: index)
                                        } else {
                                            setBid(max(entry.bid! - 1, range.lowerBound), seatIndex: seatIndex, at: index)
                                        }
                                    },
                                    onPlus: {
                                        if untouched {
                                            setBid(min(1, range.upperBound), seatIndex: seatIndex, at: index)
                                        } else {
                                            setBid(min(entry.bid! + 1, range.upperBound), seatIndex: seatIndex, at: index)
                                        }
                                    }
                                )
                            }
                            .padding(.vertical, 8)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.cardSurface.overlay(untouched ? Color.feltGreen.opacity(0.05) : Color.clear))
                        }
                    }
                }
            } header: {
                Text("Players")
                    .foregroundStyle(Color.paperSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                footerText
                    .font(.system(size: footerSize, weight: .semibold))
                    .foregroundStyle(Color.paperSecondary)
                PrimaryActionButton(title: "Confirm Bids", isDisabled: !allBidsIn, action: onConfirm)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Color.paperBase.opacity(0.96))
        }
    }

    /// "Bids: **S** of **N** tricks" from the very first render (S starts
    /// at 0) — both the running sum and the round's trick count are hero
    /// numbers via `heroNumber`, with only the connective words at the
    /// ambient secondary size. No "so far"/"waiting on <name>" suffix: the
    /// turn-aware per-row status (`firstWaitingSeatIndex`, above) already
    /// carries that information.
    private var footerText: Text {
        Text("Bids: ")
            + heroNumber(bidTotal)
            + Text(" of ")
            + heroNumber(round.roundNumber)
            + Text(" tricks")
    }

    private func setBid(_ value: Int, seatIndex: Int, at index: Int) {
        var updated = round.entries
        updated[index].bid = value
        round.entries = updated
        // Round 1's first bid interaction pins down where bidding actually
        // starts at this table — see `Game.firstBidderSeat`'s doc comment.
        // Only round 1 infers, and only once; later rounds/taps never
        // overwrite it. The saveNow() below persists both mutations together.
        if round.roundNumber == 1 && game.firstBidderSeat == nil {
            game.firstBidderSeat = seatIndex
        }
        modelContext.saveNow()
    }
}

/// C2: enter tricks taken. A trick count starts nil ("untouched") and
/// renders dimmed with no hit/miss tag until the player taps minus (commits
/// 0) or plus (commits 1). "Confirm Round" is disabled until every trick
/// count is non-nil.
private struct ResultsView: View {
    @Bindable var game: Game
    @Bindable var round: Round
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var themeManager = ThemeManager.shared
    let onConfirm: () -> Void

    private var range: ClosedRange<Int> { WizardEngine.validRange(roundNumber: round.roundNumber) }

    /// PRD C2: "Tricks entered: k of X" — k is the SUM of tricks taken and X
    /// the number of tricks that exist this round (= the round number).
    private var trickTotal: Int { round.entries.compactMap(\.tricksTaken).reduce(0, +) }

    /// "Confirm Round" label + enabled state. An unconditional completeness
    /// floor — mirroring `BiddingView.allBidsIn` — always gates first: any
    /// entry still missing a `tricksTaken` disables the button with a
    /// "Waiting on N player(s)" label, regardless of the house "trick total
    /// check" toggle (previously, with the rule off, the button was fully
    /// permissive and could confirm with nil entries still on the board).
    /// Once every entry is in, the trick-total tally takes over when the
    /// rule is on: short of the round's trick count disables with an
    /// "Enter N More" count-down, over disables with "N Too Many", and
    /// exactly on target enables with the normal label. With the rule off,
    /// that sum-vs-N gating stays off — completeness alone is enough.
    private var confirmState: (label: String, disabled: Bool) {
        let missing = round.entries.filter { $0.tricksTaken == nil }.count
        if missing > 0 {
            return ("Waiting on \(missing) player\(missing == 1 ? "" : "s")", true)
        }
        guard game.rulesSnapshot.trickTotalCheckEnabled else { return ("Confirm Round", false) }
        let diff = trickTotal - round.roundNumber
        if diff < 0 { return ("Enter \(-diff) More Trick\(-diff == 1 ? "" : "s")", true) }
        if diff > 0 { return ("\(diff) Too Many", true) }
        return ("Confirm Round", false)
    }

    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 17.5
    // Caption-sized (not subheadline 14pt): this column's intrinsic width
    // is `max(name width, pts width)` in the leading `VStack`, and shaving
    // the "N pts" text down a notch buys the fixed chip+slot+stepper group
    // on the right a little more breathing room for a full 6-player table.
    @ScaledMetric(relativeTo: .caption) private var subInfoSize: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var footerSize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .body) private var needsChipSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var outcomeDeltaSize: CGFloat = 15
    // 54pt (not the ~64pt first tried): a full row — name/pts column, chip,
    // slot, and the fixed-size `SegmentedStepper` — didn't fit on one line
    // at 64pt even at 4 players; measured empirically against the iPhone
    // 16 Pro Max sim until every row stopped wrapping. Still comfortably
    // fits "+220"/"−220", the widest deltas the engine produces.
    @ScaledMetric(relativeTo: .body) private var outcomeSlotWidth: CGFloat = 54
    @ScaledMetric(relativeTo: .subheadline) private var tricksSubtitleBaseSize: CGFloat = 17
    @ScaledMetric(relativeTo: .largeTitle) private var tricksSubtitleCountSize: CGFloat = 20

    /// Whether `participant` deals this round: the inferred dealer (last
    /// seat in bid order) once `game.firstBidderSeat` is known, otherwise
    /// the old toggle-driven `Round.dealerPlayerId` — never both, so a row
    /// never shows two dealer tags.
    private func isDealer(_ participant: Participant) -> Bool {
        if game.firstBidderSeat != nil {
            let order = game.bidOrder(forRound: round.roundNumber)
            guard let seatIndex = game.participants.firstIndex(where: { $0.playerId == participant.playerId }) else { return false }
            return order.last == seatIndex
        }
        return false  // never guess the dealer before round 1's first bid
    }

    /// The dealer's display name for `tricksSubtitleText`: the inferred
    /// dealer when known, else the old toggle-driven
    /// `Round.dealerPlayerId`, else nil — same precedence as
    /// `BiddingView.currentDealerName`.
    private var currentDealerName: String? {
        if game.firstBidderSeat != nil {
            let order = game.bidOrder(forRound: round.roundNumber)
            guard let dealerSeat = order.last, game.participants.indices.contains(dealerSeat) else { return nil }
            return game.participants[dealerSeat].displayNameSnapshot
        }
        // No positional guess before inference — see game-night feedback.
        return nil
    }

    /// "Tricks must total **N**" with the round's trick count as the hero
    /// (20pt heavy), appending " · <dealer> deals" once the dealer is
    /// known — mirrors `BiddingView.dealSubtitleText`'s enlarged deal-line
    /// treatment sibling to `ScreenHeader`. Restores the full header block
    /// this screen had before a since-reverted pass replaced it with a
    /// single compact line + nav-bar title; `BiddingView`'s equivalent
    /// header was never touched, so the two screens had drifted apart.
    private var tricksSubtitleText: Text {
        let n = round.roundNumber
        var text = Text("Tricks must total ")
            .font(.system(size: tricksSubtitleBaseSize, weight: .semibold))
            .foregroundStyle(.secondary)
            + Text("\(n)")
            .font(.system(size: tricksSubtitleCountSize, weight: .heavy))
            .foregroundStyle(.primary)
        if let currentDealerName {
            text = text + Text(" · \(currentDealerName) deals")
                .font(.system(size: tricksSubtitleBaseSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        return text
    }

    /// The reserved-size outcome slot: just the round delta ("+40"/"−10"),
    /// bold and colored (felt green on a hit, terracotta on a miss) — no
    /// "Hit ·"/"Miss ·" words, since color alone carries that meaning and
    /// dropping them is what keeps the whole row (name, chip, slot,
    /// stepper) on one line for a full 6-player table. Always the same
    /// fixed-width frame, opacity-toggled rather than conditionally
    /// inserted, so no row ever changes height or shifts its stepper
    /// column depending on whether tricks have been entered yet — this is
    /// the screen that sits open all hand, so it must never jump around as
    /// players tap in their tricks.
    @ViewBuilder
    private func outcomeSlot(entry: RoundEntry) -> some View {
        let hasResult = entry.bid != nil && entry.tricksTaken != nil
        let bid = entry.bid ?? 0
        let tricks = entry.tricksTaken ?? 0
        let score = WizardEngine.roundScore(bid: bid, tricksTaken: tricks)
        let hit = bid == tricks
        Text(ScoreFormat.delta(score))
            .font(.system(size: outcomeDeltaSize, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(hit ? Color.feltGreen : Color.terracotta)
            .frame(width: outcomeSlotWidth, alignment: .trailing)
            .opacity(hasResult ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: hasResult)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    ScreenHeader(
                        eyebrow: "Round \(round.roundNumber) of \(game.totalRounds)",
                        title: "Enter Tricks",
                        subtitle: nil
                    )
                    tricksSubtitleText
                        .padding(.horizontal, 4)
                        // Sibling of `ScreenHeader`, so it doesn't get that
                        // view's own bottom padding — see `BiddingView`'s
                        // matching comment on `dealSubtitleText`.
                        .padding(.bottom, 4)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // Rendered in `game.bidOrder(forRound:)` order — see
            // `BiddingView`'s identical row ordering above.
            Section {
                ForEach(game.bidOrder(forRound: round.roundNumber), id: \.self) { seatIndex in
                    if game.participants.indices.contains(seatIndex) {
                        let participant = game.participants[seatIndex]
                        if let index = round.entries.firstIndex(where: { $0.playerId == participant.playerId }) {
                            let entry = round.entries[index]
                            let untouched = entry.tricksTaken == nil
                            // Single line, matching `BiddingView`'s row
                            // shape: [name + pts] [flexible gap] [Needs
                            // chip] [reserved outcome slot] [stepper]. The
                            // outcome tag used to stack above the stepper
                            // in its own column — moving it inline (and
                            // dropping its "Hit ·"/"Miss ·" words, see
                            // `outcomeSlot`) is what makes room for that
                            // without wrapping to a second line on a full
                            // 6-player table.
                            HStack(spacing: 6) {
                                // LEFT: name + running total before this
                                // round. The dealer tag sits ABOVE the name
                                // (not inline beside it) so it adds height,
                                // not width — inline, it widened this
                                // column just for the dealer's row, which
                                // shoved the "Needs" chip and stepper
                                // column out of alignment with every other
                                // row.
                                VStack(alignment: .leading, spacing: 2) {
                                    if isDealer(participant) {
                                        DealerTag()
                                    }
                                    Text(participant.displayNameSnapshot)
                                        .font(.system(size: nameSize, weight: .bold))
                                        .lineLimit(1)
                                    Text("\(game.runningTotal(for: participant.playerId)) pts")
                                        .font(.system(size: subInfoSize, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 4)

                                // The bid target is the visual anchor for
                                // this "live dashboard" screen — a
                                // prominent chip, not a small caption.
                                Text("Needs \(entry.bid ?? 0)")
                                    .font(.system(size: needsChipSize, weight: .bold))
                                    .foregroundStyle(Color.feltGreen)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.feltGreen.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                outcomeSlot(entry: entry)

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
                            .padding(.vertical, 8)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.cardSurface.overlay(untouched ? Color.feltGreen.opacity(0.05) : Color.clear))
                        }
                    }
                }
            } header: {
                Text("Players")
                    .foregroundStyle(Color.paperSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                (Text("Tricks entered: ") + Text("\(trickTotal) of \(round.roundNumber)").fontWeight(.bold))
                    .font(.system(size: footerSize, weight: .semibold))
                    .foregroundStyle(Color.paperSecondary)
                PrimaryActionButton(title: confirmState.label, isDisabled: confirmState.disabled, action: onConfirm)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Color.paperBase.opacity(0.96))
        }
    }

    private func setTricks(_ value: Int, at index: Int) {
        var updated = round.entries
        updated[index].tricksTaken = value
        round.entries = updated
        modelContext.saveNow()
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
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var themeManager = ThemeManager.shared
    let onSave: () -> Void

    private var range: ClosedRange<Int> { WizardEngine.validRange(roundNumber: round.roundNumber) }

    /// A complete round's entries always have non-nil bid/tricks, but the
    /// model type allows `nil` — treated defensively as 0 here.
    private var trickTotal: Int { round.entries.reduce(0) { $0 + ($1.tricksTaken ?? 0) } }

    /// "Save Changes" label + enabled state — same state-driven gating
    /// `ResultsView.confirmState` uses, just against the base "Save
    /// Changes" label instead of "Confirm Round" once the count matches.
    /// Same unconditional completeness floor as `ResultsView.confirmState`;
    /// a `.complete` round's entries are always non-nil in practice, so this
    /// is purely defensive here.
    private var saveState: (label: String, disabled: Bool) {
        let missing = round.entries.filter { $0.tricksTaken == nil }.count
        if missing > 0 {
            return ("Waiting on \(missing) player\(missing == 1 ? "" : "s")", true)
        }
        guard game.rulesSnapshot.trickTotalCheckEnabled else { return ("Save Changes", false) }
        let diff = trickTotal - round.roundNumber
        if diff < 0 { return ("Enter \(-diff) More Trick\(-diff == 1 ? "" : "s")", true) }
        if diff > 0 { return ("\(diff) Too Many", true) }
        return ("Save Changes", false)
    }

    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 17.5
    @ScaledMetric(relativeTo: .caption) private var tagSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var footerSize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .caption) private var fieldLabelSize: CGFloat = 12

    /// Whether `participant` deals this round: the inferred dealer (last
    /// seat in bid order) once `game.firstBidderSeat` is known, otherwise
    /// the old toggle-driven `Round.dealerPlayerId` — never both, so a row
    /// never shows two dealer tags.
    private func isDealer(_ participant: Participant) -> Bool {
        if game.firstBidderSeat != nil {
            let order = game.bidOrder(forRound: round.roundNumber)
            guard let seatIndex = game.participants.firstIndex(where: { $0.playerId == participant.playerId }) else { return false }
            return order.last == seatIndex
        }
        return false  // never guess the dealer before round 1's first bid
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

            // Rendered in `game.bidOrder(forRound:)` order — see
            // `BiddingView`'s identical row ordering above.
            Section {
                ForEach(game.bidOrder(forRound: round.roundNumber), id: \.self) { seatIndex in
                    if game.participants.indices.contains(seatIndex) {
                        let participant = game.participants[seatIndex]
                        if let index = round.entries.firstIndex(where: { $0.playerId == participant.playerId }) {
                            editRow(participant: participant, index: index)
                        }
                    }
                }
            } header: {
                Text("Players")
                    .foregroundStyle(Color.paperSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                (Text("Tricks entered: ") + Text("\(trickTotal) of \(round.roundNumber)").fontWeight(.bold))
                    .font(.system(size: footerSize, weight: .semibold))
                    .foregroundStyle(Color.paperSecondary)
                PrimaryActionButton(title: saveState.label, isDisabled: saveState.disabled, action: onSave)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Color.paperBase.opacity(0.96))
        }
    }

    private func editRow(participant: Participant, index: Int) -> some View {
        let entry = round.entries[index]
        // A never-entered entry (both bid and tricksTaken nil — e.g. a
        // player backfilled into a round that closed bidding before they
        // joined) renders as untouched: an em dash instead of a fake
        // "Hit · +20" tag, and dimmed-nil steppers instead of implying a
        // real 0. An entry with only one side nil (shouldn't happen for a
        // `.complete` round) still falls back to the `?? 0` reading below.
        let untouched = entry.bid == nil && entry.tricksTaken == nil
        let bid = entry.bid ?? 0
        let tricks = entry.tricksTaken ?? 0
        let hit = bid == tricks
        let score = WizardEngine.roundScore(bid: bid, tricksTaken: tricks)

        return VStack(alignment: .leading, spacing: 10) {
            // Dealer tag above the name (not inline beside it), matching
            // `ResultsView`'s row — see that view's comment on why inline
            // placement misaligns sibling chip/column layout.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if isDealer(participant) {
                        DealerTag()
                    }
                    Text(participant.displayNameSnapshot)
                        .font(.system(size: nameSize, weight: .bold))
                }
                Spacer()
                if untouched {
                    Text("—")
                        .font(.system(size: tagSize, weight: .bold))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(hit ? "Hit" : "Miss") · \(ScoreFormat.delta(score))")
                        .font(.system(size: tagSize, weight: .bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(hit ? Color.feltGreen.opacity(0.14) : Color.terracotta.opacity(0.13))
                        .foregroundStyle(hit ? Color.feltGreen : Color.terracotta)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bid")
                        .font(.system(size: fieldLabelSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                    SegmentedStepper(
                        displayValue: bid,
                        dimmed: untouched,
                        minusEnabled: untouched || bid > range.lowerBound,
                        plusEnabled: untouched || bid < range.upperBound,
                        onMinus: { setBid(untouched ? range.lowerBound : max(bid - 1, range.lowerBound), at: index) },
                        onPlus: { setBid(untouched ? min(1, range.upperBound) : min(bid + 1, range.upperBound), at: index) }
                    )
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Took")
                        .font(.system(size: fieldLabelSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                    SegmentedStepper(
                        displayValue: tricks,
                        dimmed: untouched,
                        minusEnabled: untouched || tricks > range.lowerBound,
                        plusEnabled: untouched || tricks < range.upperBound,
                        onMinus: { setTricks(untouched ? range.lowerBound : max(tricks - 1, range.lowerBound), at: index) },
                        onPlus: { setTricks(untouched ? min(1, range.upperBound) : min(tricks + 1, range.upperBound), at: index) }
                    )
                }
            }
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.cardSurface)
    }

    private func setBid(_ value: Int, at index: Int) {
        var updated = round.entries
        updated[index].bid = value
        round.entries = updated
        modelContext.saveNow()
    }

    private func setTricks(_ value: Int, at index: Int) {
        var updated = round.entries
        updated[index].tricksTaken = value
        round.entries = updated
        modelContext.saveNow()
    }
}
