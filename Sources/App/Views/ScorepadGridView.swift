import SwiftUI
import SwiftData

/// Screen D (iPad): a two-pane table-glance layout. The iPad sits on the
/// game table where the whole table can read it, so it gets more than the
/// iPhone's single scrolling list — a fixed-width "standings panel" (same
/// data as `GameView`'s standings list, at table-readable scale) sits beside
/// the full-history scorepad grid. `GameView` decides which to show, keyed
/// off `.regular` horizontal size class (iPad is always regular-width, in
/// both orientations).
struct ScorepadGridView: View {
    @Bindable var game: Game
    @State private var navigateToRoundEntry = false
    @Environment(\.modelContext) private var modelContext
    @State private var selectedRoundNumber: Int?
    @State private var showUndoConfirm = false

    /// Fixed width of the leading "RND" column, matching the mockup's
    /// `grid-template-columns` anatomy, rescaled for the iPad pane.
    private let roundColumnWidth: CGFloat = 64
    private let outerHPadding: CGFloat = 20
    private let standingsPanelWidth: CGFloat = 400

    // Font sizes scale with Dynamic Type; the fixed geometry above (column
    // width, panel width, outer padding) stays put per the iPad layout
    // spec — only text (and the rank-circle diameter it sits beside) grows.
    @ScaledMetric(relativeTo: .subheadline) private var dealTextSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var rankCircleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var rankNumberSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var standingNameSize: CGFloat = 20
    @ScaledMetric(relativeTo: .caption) private var standingStarSize: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var standingSubtitleSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var standingDeltaSize: CGFloat = 14
    @ScaledMetric(relativeTo: .largeTitle) private var standingTotalSize: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var headerRndSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var headerNameSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption) private var headerStarSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var rowNumberSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var cellValueSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption) private var cellCumulativeSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var totalLabelSize: CGFloat = 15
    @ScaledMetric(relativeTo: .largeTitle) private var totalScoreSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var totalStarSize: CGFloat = 15

    private enum RowKind {
        case completed(deltas: [Int], cumulative: [Int])
        case current
        case future
    }

    private struct RoundRow: Identifiable {
        let id: Int
        let roundNumber: Int
        let kind: RowKind
    }

    private var participants: [Participant] { game.participants }

    private var completedRoundCount: Int {
        game.orderedRounds.filter { $0.phase == .complete }.count
    }

    private var totals: [Int] {
        participants.map { game.runningTotal(for: $0.playerId) }
    }

    /// Seat indices currently tied for the lead. Empty until at least one
    /// round has been completed, so an all-zero opening board shows no star.
    private var leaderIndices: Set<Int> {
        completedRoundCount == 0 ? [] : Set(WizardEngine.winners(totals: totals))
    }

    /// Same derivation `GameView`'s iPhone standings list uses — see
    /// `StandingsCalculator` in `Theme.swift`.
    private var standings: [GameStanding] {
        StandingsCalculator.standings(for: game)
    }

    /// The current table-leading total, used to compute each non-leading
    /// player's "X behind" subtitle in the standings panel.
    private var leaderTotal: Int {
        standings.map(\.total).max() ?? 0
    }

    /// The most recently completed round, if any — Undo reopens exactly
    /// this one, per `Game.reopenLastCompletedRound`.
    private var lastCompletedRoundNumber: Int? {
        game.orderedRounds.last { $0.phase == .complete }?.roundNumber
    }

    /// Whose deal it is this round. Prefers the inferred dealer (the last
    /// seat in `game.bidOrder(forRound:)`, once `game.firstBidderSeat` is
    /// known) for parity with `RoundEntryView`'s dealer callouts and
    /// `GameView`'s identical iPhone helper. Falls back to the old
    /// toggle-driven formula — the same one `RoundEntryView.ensureRound`
    /// seeds `Round.dealerPlayerId` with — since the current round may not
    /// be created yet.
    private var dealerName: String? {
        let n = game.currentRoundNumber
        if game.firstBidderSeat != nil {
            guard let dealerSeat = game.bidOrder(forRound: n).last, participants.indices.contains(dealerSeat) else { return nil }
            return participants[dealerSeat].displayNameSnapshot
        }
        guard game.rulesSnapshot.dealerRotationEnabled, !participants.isEmpty else { return nil }
        let index = (n - 1) % participants.count
        return participants[index].displayNameSnapshot
    }

    /// One `RoundRow` per round number 1...totalRounds, built by walking
    /// completed rounds in order and accumulating each player's running
    /// total via `Round.score(for:)` — the same derivation `Game` itself
    /// uses, never hand-computed here.
    private var rows: [RoundRow] {
        let ordered = game.orderedRounds
        let current = game.currentRoundNumber
        var running = [Int](repeating: 0, count: participants.count)
        var result: [RoundRow] = []

        for n in 1...max(game.totalRounds, 1) {
            if let round = ordered.first(where: { $0.roundNumber == n }), round.phase == .complete {
                var deltas: [Int] = []
                deltas.reserveCapacity(participants.count)
                for (i, participant) in participants.enumerated() {
                    let delta = round.score(for: participant.playerId) ?? 0
                    deltas.append(delta)
                    running[i] += delta
                }
                result.append(RoundRow(id: n, roundNumber: n, kind: .completed(deltas: deltas, cumulative: running)))
            } else if n == current {
                result.append(RoundRow(id: n, roundNumber: n, kind: .current))
            } else {
                result.append(RoundRow(id: n, roundNumber: n, kind: .future))
            }
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            standingsPanel
                .frame(width: standingsPanelWidth)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1)

            scorepadPane
        }
        .background(PaperBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if lastCompletedRoundNumber != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showUndoConfirm = true
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
            }
        }
        .confirmationDialog(
            "Reopen Round \(lastCompletedRoundNumber ?? 0)?",
            isPresented: $showUndoConfirm,
            titleVisibility: .visible
        ) {
            Button("Reopen Round", role: .destructive) {
                game.reopenLastCompletedRound()
                modelContext.saveNow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll be able to re-enter its bids and tricks. Totals update automatically.")
        }
        .navigationDestination(isPresented: $navigateToRoundEntry) {
            RoundEntryView(game: game, roundNumber: game.currentRoundNumber)
        }
        .navigationDestination(item: $selectedRoundNumber) { roundNumber in
            RoundEntryView(game: game, roundNumber: roundNumber)
        }
    }

    private var subtitleText: String {
        let n = game.currentRoundNumber
        return "Round \(n) of \(game.totalRounds) · deal \(n) card\(n == 1 ? "" : "s") each"
    }

    /// "Deal **N cards** to each player" — bold only on the card-count
    /// segment, matching the mockup's `<b>` wrapping (see `GameView`'s
    /// identical helper for the iPhone footer). When dealer rotation is
    /// on, appends " · <Name> deals".
    private var dealHelperText: Text {
        let n = game.currentRoundNumber
        var text = Text("Deal ")
            + Text("\(n) card\(n == 1 ? "" : "s")").fontWeight(.bold)
            + Text(" to each player")
        if let dealerName {
            text = text + Text(" · \(dealerName) deals")
        }
        return text
    }

    // MARK: - Left pane: standings panel

    /// The whole table can read this from across the table, so every
    /// element here is a step up from the iPhone standings row: 34pt rank
    /// circles, 20pt names, 36pt totals. Scrolls if six players ever
    /// overflow the panel; the CTA stays pinned below regardless.
    private var standingsPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(
                        eyebrow: nil,
                        title: "Scoreboard",
                        subtitle: "After Round \(completedRoundCount) of \(game.totalRounds)",
                        titleSize: 34
                    )
                    .padding(.horizontal, outerHPadding)

                    VStack(spacing: 0) {
                        ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                            standingRow(standing)
                            if index < standings.count - 1 {
                                Rectangle()
                                    .fill(Color(.separator).opacity(0.5))
                                    .frame(height: 0.5)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal, outerHPadding)
                    .padding(.top, 8)
                }
                .padding(.bottom, 12)
            }

            VStack(spacing: 10) {
                dealHelperText
                    .font(.system(size: dealTextSize, weight: .semibold))
                    .foregroundStyle(.secondary)

                PrimaryActionButton(title: "Enter Round \(game.currentRoundNumber)") {
                    navigateToRoundEntry = true
                }
            }
            .padding(outerHPadding)
        }
    }

    /// One standings-panel row: 34pt rank circle (leader gets the yellow
    /// tint + yellow number), 20pt bold name with an inline star for the
    /// leader, a 14pt "Leader"/"X behind" subtitle, a 14pt delta chip, and
    /// the 36pt heavy monospaced total.
    private func standingRow(_ standing: GameStanding) -> some View {
        let behind = max(leaderTotal - standing.total, 0)

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(standing.isLeader ? Color.yellow.opacity(0.22) : Color(.systemGray6))
                Text("\(standing.rank)")
                    .font(.system(size: rankNumberSize, weight: .bold))
                    .foregroundStyle(standing.isLeader ? .yellow : .secondary)
            }
            .frame(width: rankCircleSize, height: rankCircleSize)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(standing.name)
                        .font(.system(size: standingNameSize, weight: .bold))
                    if standing.isLeader {
                        Image(systemName: "star.fill")
                            .font(.system(size: standingStarSize))
                            .foregroundStyle(.yellow)
                    }
                }
                Text(standing.isLeader ? "Leader" : "\(behind) behind")
                    .font(.system(size: standingSubtitleSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let delta = standing.delta {
                    Text(ScoreFormat.delta(delta))
                        .font(.system(size: standingDeltaSize, weight: .bold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(delta >= 0 ? Color.green.opacity(0.14) : Color.red.opacity(0.13))
                        .foregroundStyle(delta >= 0 ? .green : .red)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(ScoreFormat.score(standing.total))
                    .font(.system(size: standingTotalSize, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 72)
    }

    // MARK: - Right pane: scorepad grid

    private var scorepadPane: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: nil, title: "Scorepad", subtitle: subtitleText, titleSize: 34)
                .padding(.horizontal, outerHPadding)

            headerRow
                .padding(.horizontal, outerHPadding)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(.separator)).frame(height: 1)
                }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                .padding(.horizontal, outerHPadding)
            }

            totalRow
                .padding(.horizontal, outerHPadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(.separator)).frame(height: 1)
                }
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("RND")
                .font(.system(size: headerRndSize, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: roundColumnWidth, alignment: .leading)

            ForEach(Array(participants.enumerated()), id: \.offset) { index, participant in
                HStack(spacing: 4) {
                    Text(participant.displayNameSnapshot)
                        .font(.system(size: headerNameSize, weight: .heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if leaderIndices.contains(index) {
                        Image(systemName: "star.fill")
                            .font(.system(size: headerStarSize))
                            .foregroundStyle(.yellow)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Body rows

    @ViewBuilder
    private func rowView(_ row: RoundRow) -> some View {
        switch row.kind {
        case .completed(let deltas, let cumulative):
            completedRow(roundNumber: row.roundNumber, deltas: deltas, cumulative: cumulative)
        case .current:
            currentRow(roundNumber: row.roundNumber)
        case .future:
            futureRow(roundNumber: row.roundNumber)
        }
    }

    /// Shared row scaffold: fixed round-number column (left-aligned, per the
    /// mockup) + flexible per-player columns whose content is centered at
    /// this scale, with the tint/corner-radius treatment `.current` needs
    /// and a hairline separator every row carries, matching `.gridrow` /
    /// `.gridrow.current` in the mockup.
    @ViewBuilder
    private func rowShell<Content: View>(
        roundNumber: Int,
        tinted: Bool,
        numberColor: Color,
        @ViewBuilder cells: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            Text("\(roundNumber)")
                .font(.system(size: rowNumberSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .frame(width: roundColumnWidth, alignment: .leading)
            cells()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(tinted ? Color.indigo.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: tinted ? 8 : 0, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.separator).opacity(0.5)).frame(height: 0.5)
        }
    }

    /// A completed round: tappable (same plain-button pattern as
    /// `currentRow`) into `RoundEntryView` for that round, which renders
    /// its edit mode since the round's phase is already `.complete`.
    private func completedRow(roundNumber: Int, deltas: [Int], cumulative: [Int]) -> some View {
        Button {
            selectedRoundNumber = roundNumber
        } label: {
            rowShell(roundNumber: roundNumber, tinted: false, numberColor: .secondary) {
                ForEach(participants.indices, id: \.self) { i in
                    VStack(alignment: .center, spacing: 1) {
                        Text(ScoreFormat.delta(deltas[i]))
                            .font(.system(size: cellValueSize, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(deltas[i] >= 0 ? .green : .red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(ScoreFormat.score(cumulative[i]))
                            .font(.system(size: cellCumulativeSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The in-progress round: indigo tint, "—" placeholders, and the whole
    /// row is a tap target into `RoundEntryView` for `game.currentRoundNumber`.
    private func currentRow(roundNumber: Int) -> some View {
        Button {
            navigateToRoundEntry = true
        } label: {
            rowShell(roundNumber: roundNumber, tinted: true, numberColor: .indigo) {
                ForEach(participants.indices, id: \.self) { _ in
                    Text("—")
                        .font(.system(size: cellValueSize, weight: .bold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func futureRow(roundNumber: Int) -> some View {
        rowShell(roundNumber: roundNumber, tinted: false, numberColor: .secondary) {
            ForEach(participants.indices, id: \.self) { _ in
                Text("·")
                    .font(.system(size: cellValueSize, weight: .bold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .opacity(0.4)
    }

    // MARK: - Pinned total row

    private var totalRow: some View {
        HStack(spacing: 0) {
            Text("Total")
                .font(.system(size: totalLabelSize, weight: .heavy))
                .foregroundStyle(.primary)
                .frame(width: roundColumnWidth, alignment: .leading)

            ForEach(Array(participants.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 4) {
                    Text(ScoreFormat.score(totals[index]))
                        .font(.system(size: totalScoreSize, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if leaderIndices.contains(index) {
                        Image(systemName: "star.fill")
                            .font(.system(size: totalStarSize))
                            .foregroundStyle(.yellow)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
