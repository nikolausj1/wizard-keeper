import SwiftUI
import SwiftData
import UIKit

extension ModelContext {
    /// Explicit save at meaningful commit points (round confirmed, bid
    /// tapped, game created). SwiftData's autosave coalesces lazily and a
    /// force-quit can beat it — game night proved it. Errors are
    /// deliberately swallowed: an in-memory state that briefly outruns disk
    /// is better than interrupting scoring.
    func saveNow() {
        guard hasChanges else { return }
        try? save()
    }
}

/// The page background used behind every screen's outermost List/ScrollView.
/// "Warm Table" restyle: light mode is a rich parchment (#EFE6D3, matching
/// `_review/restyle-E-warm-table.html`'s `--screen-bg`); dark mode is the
/// "den at night" warmed background (#1E1915) rather than plain
/// `.systemGroupedBackground`.
extension Color {
    static let paperBase = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.118, green: 0.098, blue: 0.082, alpha: 1)
            : UIColor(red: 0.937, green: 0.902, blue: 0.827, alpha: 1)
    })

    /// Interactive accent for the "Warm Table" restyle — replaces `.indigo`
    /// app-wide. Light #2F5D46 (mockup `--felt`), dark #3E7A5C (a lightened
    /// felt that holds contrast against the #1E1915 den background).
    static let feltGreen = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.243, green: 0.478, blue: 0.361, alpha: 1)
            : UIColor(red: 0.184, green: 0.365, blue: 0.275, alpha: 1)
    })

    /// Miss/negative-score accent — replaces score-semantic `.red`. Light
    /// #AE4A2C (mockup `--terracotta`), dark #C96F4A (warmed equivalent).
    static let terracotta = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.788, green: 0.435, blue: 0.290, alpha: 1)
            : UIColor(red: 0.682, green: 0.290, blue: 0.173, alpha: 1)
    })

    /// Leader/winner accent — replaces `.yellow`. Light #A0721E (mockup
    /// `--brass`), dark #C9A053 (lightened brass for legibility on the dark
    /// den background).
    static let brassGold = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.788, green: 0.627, blue: 0.325, alpha: 1)
            : UIColor(red: 0.627, green: 0.447, blue: 0.118, alpha: 1)
    })

    /// Espresso ink — used ONLY where a view hardcodes a text color today
    /// (currently just `ScreenHeader`'s title). Everywhere else, system
    /// `.primary`/`.secondary` stay as-is per the restyle brief. Light
    /// #2B2118 (mockup `--ink`), dark #EDE4D4.
    static let espressoInk = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.929, green: 0.894, blue: 0.831, alpha: 1)
            : UIColor(red: 0.169, green: 0.129, blue: 0.094, alpha: 1)
    })
}

/// The full page-background treatment: `paperBase` plus, in light mode only,
/// a barely-there tiled paper-grain texture (4.5% opacity, multiply blend)
/// over it. Dark mode renders as a flat `paperBase` fill only. Never touches
/// cards, rows, chips, or type — see `View.paperBackground()`.
struct PaperBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.paperBase
            if colorScheme == .light {
                Image("PaperGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(0.045)
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Soft warm-brown drop shadow for custom-drawn (non-List) cards in the
    /// "Warm Table" restyle — `FinalResultsView` result rows, `PlayerProfile`
    /// StatCards, and `ScorepadGridView`'s iPad standings panel. List
    /// (insetGrouped) rows can't easily take a custom shadow and are left
    /// alone; the parchment background carries the warmth for those.
    func warmCardShadow() -> some View {
        self.shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(0.12), radius: 8, x: 0, y: 3)
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

    // `titleSize` is a caller-supplied base (32 by default, 34 on the iPad
    // scorepad panes) — scaled via the multiply trick rather than a direct
    // `@ScaledMetric` so any base value tracks Dynamic Type identically.
    @ScaledMetric(relativeTo: .largeTitle) private var titleScale: CGFloat = 100
    @ScaledMetric(relativeTo: .subheadline) private var eyebrowSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize: CGFloat = 15.5

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: eyebrowSize, weight: .semibold))
                    .foregroundStyle(Color.feltGreen)
            }
            Text(title)
                .font(.system(size: titleSize * titleScale / 100, weight: .heavy))
                .foregroundStyle(Color.espressoInk)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: subtitleSize, weight: .medium))
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

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .foregroundStyle(isDisabled ? Color(.tertiaryLabel) : .white)
        .background(isDisabled ? Color(.systemGray5) : Color.feltGreen)
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

    // The value is the "big number" of the stepper — scale it (and the
    // min-width that keeps it from cramping the pill) with Dynamic Type;
    // the pill and its 44pt tap targets stay fixed, per design.
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 26
    @ScaledMetric(relativeTo: .largeTitle) private var valueMinWidth: CGFloat = 34

    var body: some View {
        HStack(spacing: 14) {
            Text("\(displayValue)")
                .font(.system(size: valueSize, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(dimmed ? Color(.tertiaryLabel) : .primary)
                .frame(minWidth: valueMinWidth, alignment: .center)

            HStack(spacing: 0) {
                stepButton(systemName: "minus", enabled: minusEnabled, action: onMinus)
                Rectangle()
                    .fill(Color.feltGreen.opacity(0.28))
                    .frame(width: 1, height: 36)
                stepButton(systemName: "plus", enabled: plusEnabled, action: onPlus)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.feltGreen.opacity(0.12))
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
                .foregroundStyle(Color.feltGreen)
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
    @ScaledMetric(relativeTo: .caption) private var textSize: CGFloat = 11

    var body: some View {
        Text("DEALER")
            .font(.system(size: textSize, weight: .bold))
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
