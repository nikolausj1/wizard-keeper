import SwiftUI
import SwiftData

/// Screen G profile: lifetime stats for one saved player, plus edit
/// (name/color) and delete affordances.
///
/// Stats are always derived on demand from completed `Game` records
/// (matching by `Participant.playerId == player.id`) — never cached on
/// `Player` — per the model's documented invariant.
struct PlayerProfileView: View {
    @Bindable var player: Player
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allGames: [Game]
    @Query private var allPlayers: [Player]

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    private var completedGamesForPlayer: [Game] {
        allGames.filter { game in
            game.status == .completed && game.participants.contains { $0.playerId == player.id }
        }
    }

    private var gamesPlayed: Int { completedGamesForPlayer.count }

    private var wins: Int {
        completedGamesForPlayer.filter { $0.winnerPlayerIds.contains(player.id) }.count
    }

    private var winPctText: String {
        guard gamesPlayed > 0 else { return "\u{2014}" }
        let pct = Int((Double(wins) / Double(gamesPlayed) * 100).rounded())
        return "\(pct)%"
    }

    private var finalTotals: [Int] {
        completedGamesForPlayer.map { $0.runningTotal(for: player.id) }
    }

    private var avgScoreText: String {
        guard !finalTotals.isEmpty else { return "\u{2014}" }
        let avg = Int((Double(finalTotals.reduce(0, +)) / Double(finalTotals.count)).rounded())
        return ScoreFormat.score(avg)
    }

    private var bestGameText: String {
        guard let best = finalTotals.max() else { return "\u{2014}" }
        return ScoreFormat.score(best)
    }

    private var exactBidRateText: String {
        var exact = 0
        var total = 0
        for game in completedGamesForPlayer {
            for round in game.orderedRounds where round.phase == .complete {
                guard let entry = round.entries.first(where: { $0.playerId == player.id }) else { continue }
                guard let bid = entry.bid, let tricksTaken = entry.tricksTaken else { continue }
                total += 1
                if bid == tricksTaken { exact += 1 }
            }
        }
        guard total > 0 else { return "\u{2014}" }
        let pct = Int((Double(exact) / Double(total) * 100).rounded())
        return "\(pct)%"
    }

    private var addedText: String {
        "Added \(player.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var otherPlayerNames: [String] {
        allPlayers.filter { $0.id != player.id }.map(\.name)
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(title: player.name, subtitle: addedText)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                statsGrid
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                    .listRowBackground(Color.clear)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete Player")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditPlayerSheet(player: player, existingNames: otherPlayerNames)
        }
        .confirmationDialog(
            "Delete \(player.name)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Player", role: .destructive) {
                deletePlayer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Past games keep their record of \(player.name).")
        }
    }

    private var statsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            StatCard(label: "Games Played", value: "\(gamesPlayed)")
            StatCard(label: "Wins", value: "\(wins)")
            StatCard(label: "Win %", value: winPctText)
            StatCard(label: "Avg Score", value: avgScoreText)
            StatCard(label: "Best Game", value: bestGameText)
            StatCard(label: "Exact-Bid Rate", value: exactBidRateText)
        }
    }

    private func deletePlayer() {
        modelContext.delete(player)
        dismiss()
    }
}

/// One stat tile in the profile's 2-column grid.
private struct StatCard: View {
    let label: String
    let value: String

    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: valueSize, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label.uppercased())
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

/// Edit sheet: rename (same validation as `AddPlayerSheet`) and re-color a
/// saved player. Saving only touches the `Player` record — past games keep
/// their own name/color snapshots untouched.
private struct EditPlayerSheet: View {
    @Bindable var player: Player
    let existingNames: [String]

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var colorId: Int = 0
    @State private var errorMessage: String?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFieldFocused)
                        .textInputAutocapitalization(.words)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Section {
                    HStack(spacing: 14) {
                        ForEach(0..<PlayerPalette.count, id: \.self) { id in
                            swatch(for: id)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Color")
                }
            }
            .navigationTitle("Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: attemptSave)
                }
            }
            .onAppear {
                name = player.name
                colorId = player.colorId
                nameFieldFocused = true
            }
        }
        .presentationDetents([.height(320)])
    }

    private func swatch(for id: Int) -> some View {
        Button {
            colorId = id
        } label: {
            Circle()
                .fill(PlayerPalette.color(id))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.primary, lineWidth: colorId == id ? 2 : 0)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
    }

    private func attemptSave() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a name."
            return
        }
        guard !existingNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "A player named \u{201C}\(trimmed)\u{201D} already exists."
            return
        }
        player.name = trimmed
        player.colorId = colorId
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PlayerProfileView(player: Player(name: "Kelly", colorId: 1))
    }
    .tint(.indigo)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
