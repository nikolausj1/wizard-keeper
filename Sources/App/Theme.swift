import SwiftUI
import SwiftData
import UIKit

/// The page background used behind every screen's outermost List/ScrollView.
/// Light mode gets the faintest warm paper shift (#F4F0E8) off pure system
/// gray, matching `_review/texture-A-paper-whisper.html`'s "Paper Whisper"
/// variant; dark mode is left byte-for-byte as `.systemGroupedBackground` —
/// this treatment is light-mode only.
extension Color {
    static let paperBase = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? .systemGroupedBackground
            : UIColor(red: 0.957, green: 0.941, blue: 0.910, alpha: 1)
    })
}

/// The full page-background treatment: `paperBase` plus, in light mode only,
/// a barely-there tiled paper-grain texture (3.5% opacity, multiply blend)
/// over it. Dark mode renders as a flat `paperBase` fill only, so it's
/// pixel-identical to today's plain system-grouped background. Never touches
/// cards, rows, chips, or type — see `View.paperBackground()`.
struct PaperBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.paperBase
            if colorScheme == .light {
                Image("PaperGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(0.035)
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Applies the shared paper-whisper page background: hides the default
    /// List/Form scroll background so `PaperBackground` shows through
    /// instead. Apply to the outermost List/ScrollView of a screen only —
    /// never to individual cards, rows, or sheets.
    func paperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
    }
}

/// Fixed 8-color palette for player avatars/rows, indexed by `Player.colorId`
/// (and `Participant.colorIdSnapshot`). All entries are system colors so
/// dark mode adapts automatically — never hardcode hex here.
enum PlayerPalette {
    private static let colors: [Color] = [
        .indigo, .teal, .orange, .pink, .purple, .blue, .green, .brown,
    ]

    /// Total number of distinct colors available in the palette.
    static var count: Int { colors.count }

    /// The color for a given `colorId`. Out-of-range ids wrap rather than
    /// crash, since ids are plain, unchecked `Int`s in the persistence layer.
    static func color(_ id: Int) -> Color {
        colors[((id % colors.count) + colors.count) % colors.count]
    }
}

/// Shared score-formatting helpers matching the Apple Native mockup: round
/// and total deltas render as "+40" / "−20" with a true minus sign (never a
/// hyphen), and always carry an explicit sign.
enum ScoreFormat {
    static func delta(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\u{2212}\(abs(value))"
    }

    /// Plain score (no explicit plus), but negatives still use the true
    /// minus sign — "−10", never "-10".
    static func score(_ value: Int) -> String {
        value < 0 ? "\u{2212}\(abs(value))" : "\(value)"
    }
}

/// Shared navbar-header block matching the Apple Native mockup's `.navbar`:
/// an optional indigo eyebrow line, a 32pt heavy large title, and an
/// optional 14.5pt secondary subtitle. iOS 17 has no `navigationSubtitle`,
/// so screens pair this with an empty `.navigationTitle("")` and
/// `.navigationBarTitleDisplayMode(.inline)`, and render this block as
/// ordinary scrolling content (e.g. the first row of a `List`) so it
/// scrolls away like a system large title rather than floating in a
/// safe-area inset.
struct ScreenHeader: View {
    var eyebrow: String?
    var title: String
    var subtitle: String?
    var titleSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.indigo)
            }
            Text(title)
                .font(.system(size: titleSize, weight: .heavy))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
}

/// Full-width 50pt CTA button matching the mockup's `.btn`: indigo fill,
/// 14pt corner radius, 17pt bold white label. `isDisabled` maps to the
/// mockup's `.btn.disabled`: a system-gray5 fill with tertiary-label text,
/// and disables interaction.
struct PrimaryActionButton: View {
    var title: String
    var isDisabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .foregroundStyle(isDisabled ? Color(.tertiaryLabel) : .white)
        .background(isDisabled ? Color(.systemGray5) : Color.indigo)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(isDisabled)
    }
}

/// Shared bid/tricks stepper matching the mockup's `.stepnum` + `.stepper`:
/// the numeric value sits left of a single pill (32pt tall, 8pt corner
/// radius, indigo-tint background) split into a minus button, a hairline
/// divider, and a plus button. The pill's visual footprint never changes
/// size — buttons at the range bounds simply fade rather than shrinking or
/// hiding the control — while each button's actual tap target is padded
/// out to 44pt tall (via a fixed frame + `.contentShape`) even though the
/// visible pill is only 32pt, so the enlarged hit area doesn't affect the
/// pill's rendered size.
struct SegmentedStepper: View {
    var displayValue: Int
    var dimmed: Bool = false
    var minusEnabled: Bool
    var plusEnabled: Bool
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("\(displayValue)")
                .font(.system(size: 26, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(dimmed ? Color(.tertiaryLabel) : .primary)
                .frame(minWidth: 34, alignment: .center)

            HStack(spacing: 0) {
                stepButton(systemName: "minus", enabled: minusEnabled, action: onMinus)
                Rectangle()
                    .fill(Color.indigo.opacity(0.28))
                    .frame(width: 1, height: 36)
                stepButton(systemName: "plus", enabled: plusEnabled, action: onPlus)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.indigo.opacity(0.12))
                    .frame(height: 36)
            )
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // The frame + contentShape live INSIDE the button label so the
            // full 44×44 area is genuinely tappable — applied outside the
            // Button they'd only pad layout, not the hit target.
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.indigo)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

/// Reads `AppSettings.hapticsEnabled` once so `.sensoryFeedback` call sites
/// can gate on it without threading a live binding through every view.
/// Pair the result with the closure-based `.sensoryFeedback(trigger:_:)`
/// overload — `{ _, _ in isEnabled ? .success : nil }` — since returning
/// `nil` from that closure is how the API suppresses playback.
enum HapticsGate {
    static func isEnabled(in context: ModelContext) -> Bool {
        (try? AppSettings.fetchOrCreate(in: context))?.hapticsEnabled ?? true
    }
}

/// Small pill tag marking the dealer's row, matching the mockup's compact
/// metadata-badge treatment: 11pt bold secondary text on a systemGray5
/// capsule. Only ever shown when `RulesSnapshot.dealerRotationEnabled`.
struct DealerTag: View {
    var body: some View {
        Text("DEALER")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
    }
}

/// One ranked row in the standings: shared between `GameView`'s iPhone
/// standings list and `ScorepadGridView`'s iPad standings panel so both
/// panes always agree on ranks, leaders, and "X behind" math.
struct GameStanding: Identifiable {
    let id: UUID
    let rank: Int
    let name: String
    let total: Int
    let delta: Int?
    let isLeader: Bool
}

/// Derives `GameStanding` rows for a `Game`: ranks via
/// `WizardEngine.placements`, leader(s) via `WizardEngine.winners` (seeded
/// only once at least one round has completed, so an all-zero opening board
/// shows no star), and each player's delta from the last *completed* round.
/// Swift's sort isn't guaranteed stable, so ties break by seating order
/// explicitly — tied players never jump around between rounds.
enum StandingsCalculator {
    static func standings(for game: Game) -> [GameStanding] {
        let participants = game.participants
        let totals = participants.map { game.runningTotal(for: $0.playerId) }
        let ranks = WizardEngine.placements(totals: totals)
        let lastCompletedRound = game.orderedRounds.last { $0.phase == .complete }
        let leaders = lastCompletedRound == nil ? [] : Set(WizardEngine.winners(totals: totals))

        return participants.enumerated().map { index, participant in
            (seat: index, standing: GameStanding(
                id: participant.playerId,
                rank: ranks[index],
                name: participant.displayNameSnapshot,
                total: totals[index],
                delta: lastCompletedRound?.score(for: participant.playerId),
                isLeader: leaders.contains(index)
            ))
        }
        .sorted { ($0.standing.rank, $0.seat) < ($1.standing.rank, $1.seat) }
        .map(\.standing)
    }
}
