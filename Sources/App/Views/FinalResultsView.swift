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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    VStack(spacing: 10) {
                        ForEach(standings) { standing in
                            resultRow(standing)
                        }
                    }
                    .padding(.horizontal)
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
                .tint(.indigo)
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
            .background(.bar)
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
                .foregroundStyle(.yellow)
                .scaleEffect(didAppear ? 1 : 0.4)
                .opacity(didAppear ? 1 : 0)
            Text(winnerNames.isEmpty ? "Game Complete" : "\(winnerNames) Wins!")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private func resultRow(_ standing: Standing) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(standing.isWinner ? Color.yellow.opacity(0.22) : Color(.systemGray6))
                Text("\(standing.rank)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(standing.isWinner ? .yellow : .secondary)
            }
            .frame(width: 34, height: 34)

            HStack(spacing: 4) {
                Text(standing.name)
                    .font(.system(size: resultNameSize, weight: .semibold))
                if standing.isWinner {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
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
    }

    private func rematch() {
        let freshRules = (try? AppSettings.fetchOrCreate(in: modelContext).makeRulesSnapshot()) ?? game.rulesSnapshot
        let newGame = Game(
            participants: game.participants,
            totalRounds: game.totalRounds,
            rulesSnapshot: freshRules
        )
        modelContext.insert(newGame)
        rematchGame = newGame
        navigateToRematch = true
    }
}
