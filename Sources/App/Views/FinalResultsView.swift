import SwiftUI
import SwiftData
import UIKit

/// Screen E: final standings once `game.status == .completed`. Winner(s)
/// get a gold star and a brief spring scale-in. "Rematch" seats the same
/// participants in a fresh game; "Done" pops back to Home.
struct FinalResultsView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var didAppear = false
    @State private var rematchGame: Game?
    @State private var navigateToRematch = false
    @State private var showUndoConfirm = false
    @State private var hapticsEnabled = true
    @State private var recapImage: UIImage?

    // Dynamic Type: sizes below are `@ScaledMetric`-driven rather than
    // fixed literals so this screen scales with the system text size.
    @ScaledMetric(relativeTo: .largeTitle) private var winnerStarSize: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var resultNameSize: CGFloat = 18
    @ScaledMetric(relativeTo: .largeTitle) private var resultTotalSize: CGFloat = 30

    /// The most recently completed round, if any — Undo reopens exactly
    /// this one, per `Game.reopenLastCompletedRound`. Once tapped, the
    /// game's status reverts to `.inProgress` and `GameView` (this view's
    /// parent, which branches on `game.status`) swaps back to its
    /// in-progress body automatically.
    private var lastCompletedRoundNumber: Int? {
        game.orderedRounds.last { $0.phase == .complete }?.roundNumber
    }

    private struct Standing: Identifiable {
        let id: UUID
        let rank: Int
        let name: String
        let colorId: Int
        let total: Int
        let isWinner: Bool
    }

    private var standings: [Standing] {
        let participants = game.participants
        let totals = participants.map { game.runningTotal(for: $0.playerId) }
        let ranks = WizardEngine.placements(totals: totals)
        let winnerIds = Set(game.winnerPlayerIds)

        return participants.enumerated().map { index, participant in
            (seat: index, standing: Standing(
                id: participant.playerId,
                rank: ranks[index],
                name: participant.displayNameSnapshot,
                colorId: participant.colorIdSnapshot,
                total: totals[index],
                isWinner: winnerIds.contains(participant.playerId)
            ))
        }
        // Stable tie ordering: rank first, then seating order.
        .sorted { ($0.standing.rank, $0.seat) < ($1.standing.rank, $1.seat) }
        .map(\.standing)
    }

    private var winnerNames: String {
        standings.filter(\.isWinner).map(\.name).joined(separator: " & ")
    }

    /// The first winner in standings order — `announceWinner` only ever
    /// calls out one name, even when multiple players tied for the win.
    private var firstWinnerName: String? {
        standings.first(where: \.isWinner)?.name
    }

    /// The worst-placed standing's name, unless that player is also a
    /// winner (e.g. everyone tied) — in which case there's no "last place"
    /// to call out.
    private var lastPlaceName: String? {
        guard let last = standings.last, !last.isWinner else { return nil }
        return last.name
    }

    /// Up to 3 full-game narrative insights (perfect records, streaks,
    /// round-of-the-game, position fallbacks) computed from every completed
    /// round of this now-finished game — see `Game.gameStoryInsights`.
    /// Feeds both the on-screen "Game Story" section and the "Hear the
    /// Call" wrap-up broadcast.
    private var gameStory: [GameInsights.Insight] {
        game.gameStoryInsights
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    hearTheCallButton
                    VStack(spacing: 10) {
                        ForEach(standings) { standing in
                            resultRow(standing)
                        }
                    }
                    .padding(.horizontal)
                    if !gameStory.isEmpty {
                        gameStorySection
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
            .paperBackground()

            VStack(spacing: 12) {
                Button(action: rematch) {
                    Text("Rematch")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.appTint)
                .controlSize(.large)

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
            .background(Color.paperBase.opacity(0.96))
        }
        .navigationTitle("Final Results")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if let recapImage {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(
                        item: Image(uiImage: recapImage),
                        preview: SharePreview("Game Recap", image: Image(uiImage: recapImage))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
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
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                didAppear = true
            }
            if recapImage == nil {
                recapImage = RecapCardRenderer.renderRecapImage(for: game)
            }
        }
        .task { hapticsEnabled = HapticsGate.isEnabled(in: modelContext) }
        .sensoryFeedback(trigger: didAppear) { _, _ in hapticsEnabled ? .success : nil }
        .navigationDestination(isPresented: $navigateToRematch) {
            if let rematchGame {
                GameView(game: rematchGame)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: winnerStarSize))
                .foregroundStyle(Color.brassGold)
                .scaleEffect(didAppear ? 1 : 0.4)
                .opacity(didAppear ? 1 : 0)
            Text(winnerNames.isEmpty ? "Game Complete" : "\(winnerNames) Wins!")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    /// "Hear the Call": plays the game wrap-up broadcast (winner callout,
    /// up to 2 of `gameStory`'s narrative beats, and — on Spicy+ styles — a
    /// last-place roast) via `AnnouncerPlayer.announceGameWrap`. Hidden
    /// entirely when there's no winner to announce (shouldn't happen once
    /// the game is complete, but guards the empty-standings edge case).
    @ViewBuilder
    private var hearTheCallButton: some View {
        if let firstWinnerName {
            Button {
                let settings = try? AppSettings.fetchOrCreate(in: modelContext)
                AnnouncerPlayer.shared.announceGameWrap(
                    winnerName: firstWinnerName,
                    lastPlaceName: lastPlaceName,
                    insights: gameStory,
                    voice: settings?.announcerVoiceSelection ?? .charlie,
                    style: settings?.announcerStyleSelection ?? .classic
                )
            } label: {
                Label("Hear the Call", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.appTint)
        }
    }

    /// "Game Story": up to 3 rows of full-game narrative below the
    /// standings, same warm-card style as `resultRow` so both read as one
    /// section family.
    private var gameStorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Game Story")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.paperSecondary)
                .padding(.horizontal, 4)
            VStack(spacing: 10) {
                ForEach(Array(gameStory.enumerated()), id: \.offset) { _, insight in
                    storyRow(insight)
                }
            }
        }
    }

    private func storyRow(_ insight: GameInsights.Insight) -> some View {
        HStack(spacing: 10) {
            Image(systemName: insight.icon)
                .foregroundStyle(Color.feltGreen)
                .frame(width: 20)
            Text(insight.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .warmCardShadow()
    }

    private func resultRow(_ standing: Standing) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(standing.isWinner ? Color.brassGold.opacity(0.22) : Color(.systemGray6))
                Text("\(standing.rank)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(standing.isWinner ? Color.brassGold : .secondary)
            }
            .frame(width: 34, height: 34)

            HStack(spacing: 4) {
                Text(standing.name)
                    .font(.system(size: resultNameSize, weight: .semibold))
                if standing.isWinner {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.brassGold)
                }
            }

            Spacer()

            Text(ScoreFormat.score(standing.total))
                .font(.system(size: resultTotalSize, weight: .heavy))
                .monospacedDigit()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .warmCardShadow()
    }

    private func rematch() {
        let freshRules = (try? AppSettings.fetchOrCreate(in: modelContext).makeRulesSnapshot()) ?? game.rulesSnapshot
        // `game.totalRounds` can exceed the legal max for this roster if a
        // player joined mid-game (the cap only ever grows to accommodate a
        // bigger table, `totalRounds` itself isn't retroactively trimmed) —
        // clamp to whatever `WizardEngine` allows for the carried-over
        // participant count before seeding the rematch.
        let clampedRounds = min(
            game.totalRounds,
            WizardEngine.totalRounds(playerCount: game.participants.count) ?? game.totalRounds
        )
        let newGame = Game(
            participants: game.participants,
            totalRounds: clampedRounds,
            rulesSnapshot: freshRules
        )
        modelContext.insert(newGame)
        modelContext.saveNow()
        rematchGame = newGame
        navigateToRematch = true
    }
}
