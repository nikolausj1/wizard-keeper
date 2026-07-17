import SwiftUI
import UIKit

/// Plain-value payload for `RecapCardView` — deliberately holds no
/// `ModelContext` or SwiftData model references so the card can render off
/// the main data graph (and, incidentally, so it's trivial to preview).
struct RecapData {
    struct Row: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let total: Int
        let isWinner: Bool
        /// `Participant.colorIdSnapshot` — feeds `PlayerPalette.color(_:)`
        /// for this player's line in the score-over-time chart.
        let colorId: Int
    }

    /// One player's cumulative-score line for the "Score Over Time" chart.
    struct Series: Identifiable {
        let id = UUID()
        let name: String
        let colorId: Int
        let isWinner: Bool
        /// Cumulative total after each round, index 0 = pregame (always 0)
        /// through index N = total after the Nth *completed* round. A
        /// player with no entry in an early round (mid-game joiner)
        /// contributes 0 for that round — same as `Round.score(for:)` —
        /// so their line simply stays flat at 0 until they start scoring.
        let points: [Int]
    }

    let winnerNames: String
    let dateText: String
    let roundsText: String
    let standings: [Row]
    /// Same player order as `standings` (rank order, winner first).
    let series: [Series]
    /// Up to 2 game-story lines (perfect records, streaks, round-of-the-
    /// game, etc.) — the same `Game.gameStoryInsights` computation
    /// `FinalResultsView`'s "Game Story" section shows on-screen, trimmed
    /// to fit the fixed card canvas.
    let storyLines: [String]

    /// "\(winnerNames) Wins!" or "Game Complete" when there's no winner
    /// (e.g. an all-tie edge case with no seeded rounds).
    var headline: String {
        winnerNames.isEmpty ? "Game Complete" : "\(winnerNames) Wins!"
    }
}

/// A fixed-size share card summarizing a completed game's final standings,
/// designed purely for image EXPORT via `ImageRenderer` — not for on-screen
/// layout. Renders at a fixed 360×450pt canvas; callers scale the renderer
/// (not this view) up to the final pixel size. Every size in this file is a
/// literal constant — this view is exempt from the app's Dynamic Type
/// conversion pass, since a share-card canvas has no reflow room.
struct RecapCardView: View {
    let data: RecapData
    @ObservedObject private var themeManager = ThemeManager.shared

    /// Card canvas size in points. Render with `ImageRenderer.scale = 3` to
    /// get a 1080×1755px export. Grew from the original 360×450 to make
    /// room for the "Score Over Time" chart panel without crowding the
    /// existing sections — this image gets texted to family, so every
    /// section keeps its own breathing room.
    static let cardSize = CGSize(width: 360, height: 585)

    /// Standings rows beyond this are dropped — six rows is what the fixed
    /// canvas height comfortably fits.
    private static let maxRows = 6

    private var visibleStandings: [RecapData.Row] {
        Array(data.standings.prefix(Self.maxRows))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            standingsList
                .padding(.top, 14)
            if data.series.contains(where: { $0.points.count > 1 }) {
                scoreChartSection
                    .padding(.top, 14)
            }
            if !data.storyLines.isEmpty {
                storySection
                    .padding(.top, 10)
            }
            Spacer(minLength: 8)
            footer
        }
        .padding(20)
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(Color.paperBase)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("WIZARD KEEPER")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color.feltGreen)

            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.brassGold)
                Text(data.headline)
                    .font(.system(size: 26, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            Text("\(data.dateText) \u{00B7} \(data.roundsText)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var standingsList: some View {
        // 6pt (not 8): shrunk slightly to leave room for `storySection`
        // below without growing the fixed 360×450 canvas — see that
        // property's doc comment.
        VStack(spacing: 6) {
            ForEach(visibleStandings) { row in
                standingRow(row)
            }
        }
    }

    private func standingRow(_ row: RecapData.Row) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(row.isWinner ? Color.brassGold.opacity(0.22) : Color.warmDisabled.opacity(0.55))
                Text("\(row.rank)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(row.isWinner ? Color.brassGold : .secondary)
            }
            .frame(width: 22, height: 22)

            HStack(spacing: 4) {
                Text(row.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if row.isWinner {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.brassGold)
                }
            }

            Spacer()

            Text(ScoreFormat.score(row.total))
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(row.isWinner ? Color.brassGold.opacity(0.12) : Color.cardSurface)
        )
    }

    /// "SCORE OVER TIME" panel: a rounded `cardSurface` panel matching the
    /// standings rows' material, holding a small section label (same
    /// tracked-caps style as the "WIZARD KEEPER" header eyebrow, just
    /// smaller and muted) above the chart itself.
    private var scoreChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCORE OVER TIME")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            ScoreChartView(series: data.series)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.cardSurface)
        )
    }

    /// Up to 2 game-story lines below a divider — icon-free, small, and
    /// secondary so they read as a caption to the standings rather than
    /// competing with them. Kept short enough (single line, truncating) to
    /// fit the fixed canvas even with 6 standings rows above.
    private var storySection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider()
                .padding(.bottom, 3)
            ForEach(Array(data.storyLines.prefix(2).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var footer: some View {
        Text("Scored with Wizard Keeper")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

/// A cumulative-score line chart, one polyline per player, drawn with
/// plain SwiftUI `Canvas`/`Path` — deliberately NOT the `Charts` framework,
/// so behavior stays predictable inside `ImageRenderer` (see this file's
/// header comment). Every size here is a literal constant, matching the
/// rest of this fixed-canvas card: the chart's overall width is driven by
/// its parent (`scoreChartSection`'s `RoundedRectangle`, which spans the
/// card's full content width), but every lane inside it — the y-axis
/// gutter, the plot itself, the right-edge name lane — is a fixed point
/// value tuned against the 360pt card width.
private struct ScoreChartView: View {
    let series: [RecapData.Series]

    private static let chartHeight: CGFloat = 150
    private static let leftAxisWidth: CGFloat = 24
    private static let rightLabelWidth: CGFloat = 58
    private static let labelFontSize: CGFloat = 9
    /// Minimum vertical gap between two end-of-line name labels before the
    /// declutter pass starts pushing them apart.
    private static let minLabelGap: CGFloat = 12

    /// Number of *completed* rounds represented (points.count is rounds+1,
    /// index 0 being the pregame zero baseline).
    private var roundCount: Int {
        (series.map(\.points.count).max() ?? 1) - 1
    }

    private var allValues: [Int] {
        series.flatMap(\.points)
    }

    /// Y-axis bounds: padded ~12% past the data's min/max, then rounded
    /// outward to the nearest 50 so gridlines land on clean numbers.
    /// Falls back to a minimum 40-point span so a dead-flat or single-round
    /// series (e.g. a freshly-started game) still draws a legible panel
    /// instead of a zero-height line.
    private var yRange: (min: Double, max: Double) {
        let rawMin = Double(allValues.min() ?? 0)
        let rawMax = Double(allValues.max() ?? 0)
        let span = max(rawMax - rawMin, 40)
        let padding = span * 0.12
        var niceMin = ((rawMin - padding) / 50).rounded(.down) * 50
        var niceMax = ((rawMax + padding) / 50).rounded(.up) * 50
        if niceMin == niceMax {
            niceMin -= 50
            niceMax += 50
        }
        return (niceMin, niceMax)
    }

    /// Gridline spacing chosen so 3–5 lines cover the y-range, picked from
    /// a fixed ladder of clean step sizes.
    private var gridStep: Double {
        let range = yRange.max - yRange.min
        let candidates: [Double] = [50, 100, 150, 200, 250, 300, 400, 500, 750, 1000, 1500, 2000]
        return candidates.first { range / $0 <= 5 } ?? candidates.last!
    }

    private var gridLines: [Double] {
        let range = yRange
        var lines: [Double] = []
        var value = (range.min / gridStep).rounded(.up) * gridStep
        while value <= range.max + 0.01 {
            lines.append(value)
            value += gridStep
        }
        return lines
    }

    /// Every round if there are 10 or fewer, else every 2nd (≤20) or 3rd.
    private var xTickInterval: Int {
        if roundCount <= 10 { return 1 }
        if roundCount <= 20 { return 2 }
        return 3
    }

    private var xTicks: [Int] {
        guard roundCount > 0 else { return [0] }
        var ticks = Array(stride(from: 0, through: roundCount, by: xTickInterval))
        if ticks.last != roundCount {
            // The final round always gets a tick; drop the previous
            // stride-tick when it lands one round away so the two labels
            // don't collide (e.g. "14 15" on a 15-round game at interval 2).
            if let last = ticks.last, roundCount - last < xTickInterval {
                ticks.removeLast()
            }
            ticks.append(roundCount)
        }
        return ticks
    }

    private func yPosition(_ value: Int, height: CGFloat) -> CGFloat {
        let range = yRange
        let fraction = (Double(value) - range.min) / (range.max - range.min)
        return height - CGFloat(fraction) * height
    }

    private func xPosition(_ index: Int, width: CGFloat) -> CGFloat {
        guard roundCount > 0 else { return 0 }
        return width * CGFloat(index) / CGFloat(roundCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                yAxisLabels
                    .frame(width: Self.leftAxisWidth, height: Self.chartHeight)
                GeometryReader { geo in
                    Canvas { context, size in
                        drawGridlines(context: context, size: size)
                        for entry in series where !entry.isWinner {
                            drawLine(entry, context: context, size: size)
                        }
                        for entry in series where entry.isWinner {
                            drawLine(entry, context: context, size: size)
                        }
                    }
                    .frame(width: geo.size.width, height: Self.chartHeight)
                }
                .frame(height: Self.chartHeight)
                endLabels
                    .frame(width: Self.rightLabelWidth, height: Self.chartHeight)
            }
            xAxisLabels
                .padding(.leading, Self.leftAxisWidth + 6)
        }
    }

    // MARK: Canvas drawing

    private func drawGridlines(context: GraphicsContext, size: CGSize) {
        let range = yRange
        for value in gridLines {
            let y = yPosition(Int(value), height: size.height)
            let isZeroLine = value == 0 && range.min < 0
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                path,
                with: .color(isZeroLine ? Color.espressoInk.opacity(0.32) : Color.espressoInk.opacity(0.09)),
                lineWidth: isZeroLine ? 1.2 : 0.75
            )
        }
    }

    private func drawLine(_ entry: RecapData.Series, context: GraphicsContext, size: CGSize) {
        guard entry.points.count > 1 else { return }
        let color = PlayerPalette.color(entry.colorId)
        var path = Path()
        for (index, value) in entry.points.enumerated() {
            let point = CGPoint(x: xPosition(index, width: size.width), y: yPosition(value, height: size.height))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        if entry.isWinner {
            // Subtle brass glow behind the winner's line: a wide, blurred,
            // translucent stroke drawn under the crisp line on top.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.stroke(path, with: .color(Color.brassGold.opacity(0.55)), lineWidth: 6)
            }
        }

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: entry.isWinner ? 3.5 : 2.5, lineCap: .round, lineJoin: .round)
        )

        guard let last = entry.points.last else { return }
        let end = CGPoint(x: xPosition(entry.points.count - 1, width: size.width), y: yPosition(last, height: size.height))
        let dotRadius: CGFloat = entry.isWinner ? 4.5 : 3.5
        let dotRect = CGRect(x: end.x - dotRadius, y: end.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(color))
        if entry.isWinner {
            context.stroke(Path(ellipseIn: dotRect.insetBy(dx: -1.5, dy: -1.5)), with: .color(Color.brassGold), lineWidth: 1.5)
        }
    }

    // MARK: Axis labels

    /// The topmost and bottommost *gridlines* (so every label sits on an
    /// actual drawn line — never a floating range extreme), plus the zero
    /// line when scores go negative. Deliberately sparse (not one label
    /// per gridline) so the narrow left gutter never crowds; any candidate
    /// that would sit within a text-height of the zero label is dropped
    /// in favor of the more meaningful 0.
    private var yAxisLabels: some View {
        var values: [Double] = []
        if let top = gridLines.last { values.append(top) }
        if let bottom = gridLines.first, bottom != gridLines.last { values.append(bottom) }
        if yRange.min < 0 && yRange.max > 0 && !values.contains(0) {
            let zeroY = yPosition(0, height: Self.chartHeight)
            values.removeAll { value in
                abs(clampedLabelY(yPosition(Int(value), height: Self.chartHeight)) - zeroY) < Self.minLabelGap
            }
            values.append(0)
        }
        return ZStack(alignment: .topTrailing) {
            ForEach(values, id: \.self) { value in
                Text(ScoreFormat.score(Int(value)))
                    .font(.system(size: Self.labelFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: Self.leftAxisWidth - 14, y: clampedLabelY(yPosition(Int(value), height: Self.chartHeight)))
            }
        }
        .frame(width: Self.leftAxisWidth, height: Self.chartHeight, alignment: .topTrailing)
    }

    private var xAxisLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(xTicks, id: \.self) { tick in
                Text("\(tick)")
                    .font(.system(size: Self.labelFontSize - 1, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: xPosition(tick, width: chartPlotWidth), y: 6)
            }
        }
        .frame(width: chartPlotWidth, height: 12, alignment: .topLeading)
    }

    /// End-of-line player-name labels in the right-hand lane, vertically
    /// decluttered so close final scores don't overlap.
    private var endLabels: some View {
        let entries = series.filter { $0.points.count > 1 }
        let rawYs = entries.map { yPosition($0.points.last ?? 0, height: Self.chartHeight) }
        let adjustedYs = declutter(rawYs, minGap: Self.minLabelGap, bounds: 5...(Self.chartHeight - 5))

        return ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                Text(entry.name)
                    .font(.system(size: Self.labelFontSize, weight: .semibold))
                    .foregroundStyle(PlayerPalette.color(entry.colorId))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: Self.rightLabelWidth - 6, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .position(x: (Self.rightLabelWidth - 6) / 2 + 3, y: adjustedYs[index])
            }
        }
        .frame(width: Self.rightLabelWidth, height: Self.chartHeight, alignment: .topLeading)
    }

    /// Keeps a y-axis label's vertical center from clipping past the top
    /// or bottom of the chart's own frame.
    private func clampedLabelY(_ y: CGFloat) -> CGFloat {
        min(max(y, 6), Self.chartHeight - 6)
    }

    /// Plot-area width mirrors `scoreChartSection`'s content width minus
    /// this view's own left-axis and right-label lanes (with their
    /// spacing) — kept as one literal so `xAxisLabels`, which sits outside
    /// the `GeometryReader` that measures the live plot width, stays in
    /// sync with it. See the type doc comment for why literals are safe
    /// here: this card's layout is entirely fixed-size.
    private var chartPlotWidth: CGFloat {
        // Card width 360 − 2×20 outer padding − 2×12 panel padding
        // − leftAxisWidth − rightLabelWidth − 2×6 HStack spacing.
        360 - 40 - 24 - Self.leftAxisWidth - Self.rightLabelWidth - 12
    }

    /// Simple greedy label-declutter: sorts by position, then walks
    /// top-to-bottom pushing any label closer than `minGap` to its
    /// predecessor down, then shifts the whole cluster back inside
    /// `bounds` if that pushed the last label out of range.
    private func declutter(_ ys: [CGFloat], minGap: CGFloat, bounds: ClosedRange<CGFloat>) -> [CGFloat] {
        guard ys.count > 1 else { return ys.map { min(max($0, bounds.lowerBound), bounds.upperBound) } }

        let order = ys.enumerated().sorted { $0.element < $1.element }
        var adjusted = order.map(\.element)
        for i in 1..<adjusted.count {
            if adjusted[i] - adjusted[i - 1] < minGap {
                adjusted[i] = adjusted[i - 1] + minGap
            }
        }
        if let last = adjusted.last, last > bounds.upperBound {
            let overflow = last - bounds.upperBound
            for i in adjusted.indices { adjusted[i] -= overflow }
        }
        if let first = adjusted.first, first < bounds.lowerBound {
            let shift = bounds.lowerBound - first
            for i in adjusted.indices { adjusted[i] += shift }
        }

        var result = [CGFloat](repeating: 0, count: ys.count)
        for (sortedIndex, (originalIndex, _)) in order.enumerated() {
            result[originalIndex] = adjusted[sortedIndex]
        }
        return result
    }
}

/// Share plumbing: builds a `RecapData` from a completed `Game` and renders
/// `RecapCardView` off-screen to a `UIImage` via `ImageRenderer`. Lives here
/// rather than on `Game`/`WizardEngine` since it's purely a presentation
/// concern for this one feature.
enum RecapCardRenderer {
    /// Derives the same rank/name/total/winner tuple `FinalResultsView` and
    /// `GameDetailView` compute locally, via the shared
    /// `StandingsCalculator` so all three stay in lockstep.
    @MainActor
    static func recapData(for game: Game) -> RecapData {
        let standings = StandingsCalculator.standings(for: game)
        let winnerIds = Set(game.winnerPlayerIds)
        let winnerNames = standings
            .filter { winnerIds.contains($0.id) }
            .map(\.name)
            .joined(separator: " & ")

        let dateText: String
        if let completedAt = game.completedAt {
            dateText = completedAt.formatted(date: .abbreviated, time: .omitted)
        } else {
            dateText = Date().formatted(date: .abbreviated, time: .omitted)
        }

        let roundsText = "\(game.totalRounds) round\(game.totalRounds == 1 ? "" : "s")"

        // `colorIdSnapshot` lives on `Participant`, not `GameStanding` —
        // look it up by id so both `rows` and `series` below can carry a
        // player color without `StandingsCalculator` needing to know about
        // it.
        let colorById = Dictionary(uniqueKeysWithValues: game.participants.map { ($0.playerId, $0.colorIdSnapshot) })

        let rows = standings.map { standing in
            RecapData.Row(
                rank: standing.rank,
                name: standing.name,
                total: standing.total,
                isWinner: winnerIds.contains(standing.id),
                colorId: colorById[standing.id] ?? 0
            )
        }

        // Cumulative-score series for the "Score Over Time" chart: walk
        // completed rounds in order, summing each via `Round.score(for:)` —
        // the same accessor `Game.runningTotal(for:)` delegates to — so a
        // mid-game joiner's series naturally stays flat at 0 (nil score)
        // until they have entries, with no score math duplicated here.
        let completedRounds = game.orderedRounds.filter { $0.phase == .complete }
        let series = standings.map { standing -> RecapData.Series in
            var points = [0]
            var running = 0
            for round in completedRounds {
                running += round.score(for: standing.id) ?? 0
                points.append(running)
            }
            return RecapData.Series(
                name: standing.name,
                colorId: colorById[standing.id] ?? 0,
                isWinner: winnerIds.contains(standing.id),
                points: points
            )
        }

        let storyLines = game.gameStoryInsights.prefix(2).map(\.text)

        return RecapData(
            winnerNames: winnerNames,
            dateText: dateText,
            roundsText: roundsText,
            standings: rows,
            series: series,
            storyLines: Array(storyLines)
        )
    }

    /// Renders a completed game's recap card to a `UIImage` at 1080×1806px
    /// (360×602pt canvas @3x). Returns `nil` only if `ImageRenderer` fails
    /// to produce a `uiImage`, which in practice shouldn't happen for a
    /// pure-SwiftUI, opaque-background view like this one.
    @MainActor
    static func renderRecapImage(for game: Game) -> UIImage? {
        let data = recapData(for: game)
        let card = RecapCardView(data: data)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

#Preview {
    RecapCardView(data: RecapData(
        winnerNames: "Kelly",
        dateText: "Jul 10, 2026",
        roundsText: "15 rounds",
        standings: [
            RecapData.Row(rank: 1, name: "Kelly", total: 310, isWinner: true, colorId: 1),
            RecapData.Row(rank: 2, name: "Justin", total: 260, isWinner: false, colorId: 0),
            RecapData.Row(rank: 3, name: "Dave", total: 150, isWinner: false, colorId: 2),
            RecapData.Row(rank: 4, name: "Nan", total: 40, isWinner: false, colorId: 3),
        ],
        series: [
            RecapData.Series(name: "Kelly", colorId: 1, isWinner: true, points: [0, 0, 0, 0, 80, 80, 130, 180, 180, 180, 230, 230, 260, 260, 310, 310]),
            RecapData.Series(name: "Justin", colorId: 0, isWinner: false, points: [0, 30, 30, 30, 30, 30, 80, 130, 150, 170, 170, 190, 190, 220, 220, 260]),
            RecapData.Series(name: "Dave", colorId: 2, isWinner: false, points: [0, 0, 0, 0, 0, -70, -70, -70, -20, -20, 30, 80, 80, 130, 150, 150]),
            RecapData.Series(name: "Nan", colorId: 3, isWinner: false, points: [0, 0, -10, -20, -20, -20, -40, -70, -10, 40, 40, 40, 40, 40, 40, 40]),
        ],
        storyLines: [
            "Kelly has hit every bid (15 for 15)",
            "Nan's +160 in round 14 is the round of the game",
        ]
    ))
    .previewLayout(.fixed(width: RecapCardView.cardSize.width, height: RecapCardView.cardSize.height))
}
