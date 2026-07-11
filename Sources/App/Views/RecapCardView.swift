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
    }

    let winnerNames: String
    let dateText: String
    let roundsText: String
    let standings: [Row]

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

    /// Card canvas size in points. Render with `ImageRenderer.scale = 3` to
    /// get a 1080×1350px export.
    static let cardSize = CGSize(width: 360, height: 450)

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
        VStack(spacing: 8) {
            ForEach(visibleStandings) { row in
                standingRow(row)
            }
        }
    }

    private func standingRow(_ row: RecapData.Row) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(row.isWinner ? Color.brassGold.opacity(0.22) : Color(.systemGray6))
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
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(row.isWinner ? Color.brassGold.opacity(0.12) : Color(.secondarySystemGroupedBackground))
        )
    }

    private var footer: some View {
        Text("Scored with Wizard Keeper")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
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

        let rows = standings.map { standing in
            RecapData.Row(
                rank: standing.rank,
                name: standing.name,
                total: standing.total,
                isWinner: winnerIds.contains(standing.id)
            )
        }

        return RecapData(winnerNames: winnerNames, dateText: dateText, roundsText: roundsText, standings: rows)
    }

    /// Renders a completed game's recap card to a `UIImage` at 1080×1350px
    /// (360×450pt canvas @3x). Returns `nil` only if `ImageRenderer` fails
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
            RecapData.Row(rank: 1, name: "Kelly", total: 310, isWinner: true),
            RecapData.Row(rank: 2, name: "Justin", total: 260, isWinner: false),
            RecapData.Row(rank: 3, name: "Dave", total: 150, isWinner: false),
            RecapData.Row(rank: 4, name: "Nan", total: 40, isWinner: false),
        ]
    ))
    .previewLayout(.fixed(width: 360, height: 450))
}
