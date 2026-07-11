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

/// One themeable color palette: the six semantic colors ("Warm Table"
/// restyle's `paperBase`/`feltGreen`/`terracotta`/`brassGold`/`espressoInk`/
/// `warmDisabled`) plus the page-background grain treatment, bundled so
/// `AppTheme` can vend a complete look in one shot. Each color is built
/// with `ThemePalette.dynamic(light:dark:)`, the same UIColor
/// dynamic-provider pattern the original static `let`s used — so
/// consuming call sites (`Color.paperBase`, `ScreenHeader`,
/// `PrimaryActionButton`, ...) never change; only where the RGB values
/// come from does.
struct ThemePalette {
    let paperBase: Color
    let feltGreen: Color
    let terracotta: Color
    let brassGold: Color
    let espressoInk: Color
    let warmDisabled: Color

    /// Accent for chrome that sits directly on the page background — nav
    /// bar buttons, `ScreenHeader` eyebrows, and the global `.tint`.
    /// Parchment keeps this identical to `feltGreen` (today's look); the
    /// dark-page themes (Card Table, Walnut) swap to brass, because a deep
    /// green control on a felt or walnut page all but vanishes while brass
    /// reads on both the dark page AND white card surfaces.
    let tint: Color

    /// Opacity of the tiled paper-grain texture in light mode (see
    /// `PaperBackground`). Ignored when `showGrain` is `false`.
    let grainOpacity: Double

    /// Whether `PaperBackground` should draw the grain texture at all —
    /// off for a felt page background (Card Table) where a paper texture
    /// reads wrong; on (at a theme-appropriate opacity) for Parchment and
    /// Walnut.
    let showGrain: Bool
}

extension ThemePalette {
    /// Builds a `Color` that resolves to `light` in light mode and `dark`
    /// in dark mode — component tuples are `(red, green, blue)` in the
    /// 0...1 range, matching `UIColor(red:green:blue:alpha:)`.
    fileprivate static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
                : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
        })
    }

    /// The original "Warm Table" palette — parchment page, felt-green
    /// accent. Default theme; values unchanged from the pre-theming
    /// static `let`s. Light mode is a rich parchment (#EFE6D3, matching
    /// `_review/restyle-E-warm-table.html`'s `--screen-bg`); dark mode is
    /// the "den at night" warmed background (#1E1915).
    static let parchment = ThemePalette(
        paperBase: dynamic(light: (0.937, 0.902, 0.827), dark: (0.118, 0.098, 0.082)),
        feltGreen: dynamic(light: (0.184, 0.365, 0.275), dark: (0.243, 0.478, 0.361)),
        terracotta: dynamic(light: (0.682, 0.290, 0.173), dark: (0.788, 0.435, 0.290)),
        brassGold: dynamic(light: (0.627, 0.447, 0.118), dark: (0.788, 0.627, 0.325)),
        espressoInk: dynamic(light: (0.169, 0.129, 0.094), dark: (0.929, 0.894, 0.831)),
        warmDisabled: dynamic(light: (0.867, 0.827, 0.753), dark: (0.227, 0.196, 0.165)),
        tint: dynamic(light: (0.184, 0.365, 0.275), dark: (0.243, 0.478, 0.361)),
        grainOpacity: 0.045,
        showGrain: true
    )

    /// Felt-table look: the page background swaps to felt green — Justin's
    /// "what would it look like with the felt green as the background and
    /// the beige somewhere else" ask (#2F5D46 light, deep felt #22352B at
    /// night). `espressoInk` flips to cream (#F2EAD8/#EFE6D3) so titles
    /// rendered on that felt page stay legible in both modes, the
    /// interactive green deepens to a forest tone that still contrasts on
    /// white system cards, and the paper grain is switched off since it
    /// only suits an actual paper background.
    static let cardTable = ThemePalette(
        paperBase: dynamic(light: (0.184, 0.365, 0.275), dark: (0.133, 0.208, 0.169)),
        feltGreen: dynamic(light: (0.122, 0.271, 0.204), dark: (0.306, 0.557, 0.424)),
        terracotta: dynamic(light: (0.788, 0.435, 0.290), dark: (0.851, 0.545, 0.412)),
        brassGold: dynamic(light: (0.788, 0.627, 0.325), dark: (0.831, 0.690, 0.416)),
        espressoInk: dynamic(light: (0.949, 0.918, 0.847), dark: (0.937, 0.902, 0.827)),
        warmDisabled: dynamic(light: (0.278, 0.420, 0.349), dark: (0.165, 0.247, 0.200)),
        tint: dynamic(light: (0.788, 0.627, 0.325), dark: (0.831, 0.690, 0.416)),
        grainOpacity: 0,
        showGrain: false
    )

    /// Warm wood look: a deep walnut page background (#4A3A28 — light mode
    /// is intentionally deep-toned, #241C12 at night), cream ink
    /// (#F2E8D5/#EDE4D4) for legibility against the wood in both modes,
    /// and a slightly stronger wood-grain-ish texture (0.06 vs.
    /// Parchment's 0.045) using the same tile.
    static let walnut = ThemePalette(
        paperBase: dynamic(light: (0.290, 0.227, 0.157), dark: (0.141, 0.110, 0.071)),
        feltGreen: dynamic(light: (0.243, 0.478, 0.361), dark: (0.243, 0.478, 0.361)),
        terracotta: dynamic(light: (0.851, 0.545, 0.412), dark: (0.851, 0.545, 0.412)),
        brassGold: dynamic(light: (0.831, 0.690, 0.416), dark: (0.831, 0.690, 0.416)),
        espressoInk: dynamic(light: (0.949, 0.910, 0.835), dark: (0.929, 0.894, 0.831)),
        warmDisabled: dynamic(light: (0.369, 0.298, 0.212), dark: (0.208, 0.157, 0.102)),
        tint: dynamic(light: (0.831, 0.690, 0.416), dark: (0.831, 0.690, 0.416)),
        grainOpacity: 0.06,
        showGrain: true
    )
}

/// Selectable app-wide color theme. Persisted as `AppSettings.appTheme`
/// (raw `Int`, matching this enum's `rawValue`) and applied globally by
/// `ThemeManager`; picked from `SettingsView`'s "Theme" row.
enum AppTheme: Int, CaseIterable, Identifiable {
    case parchment = 1
    case cardTable = 2
    case walnut = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .parchment: return "Parchment"
        case .cardTable: return "Card Table"
        case .walnut: return "Walnut"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .parchment: return .parchment
        case .cardTable: return .cardTable
        case .walnut: return .walnut
        }
    }
}

/// Live-observed holder for the app's active `AppTheme`. The `Color`
/// statics below (`.paperBase`, `.feltGreen`, `.terracotta`, `.brassGold`,
/// `.espressoInk`, `.warmDisabled`) read `ThemeManager.shared.theme
/// .palette` each time they're evaluated, so a theme switch only shows up
/// once something re-renders — `RootView` applies `.id(themeManager
/// .theme)` to its root content to force that full re-render on change.
/// `RootView` also loads the persisted theme (`AppSettings.appTheme`) into
/// this singleton at startup.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var theme: AppTheme = .parchment

    private init() {}
}

/// The six semantic colors from the "Warm Table" restyle, now sourced from
/// the active `ThemeManager.shared.theme.palette` (see `ThemePalette`)
/// instead of fixed values — consuming views read `Color.paperBase` etc.
/// exactly as before; only the theme engine underneath changed.
extension Color {
    static var paperBase: Color { ThemeManager.shared.theme.palette.paperBase }
    static var feltGreen: Color { ThemeManager.shared.theme.palette.feltGreen }
    static var terracotta: Color { ThemeManager.shared.theme.palette.terracotta }
    static var brassGold: Color { ThemeManager.shared.theme.palette.brassGold }
    static var espressoInk: Color { ThemeManager.shared.theme.palette.espressoInk }
    static var warmDisabled: Color { ThemeManager.shared.theme.palette.warmDisabled }
    static var appTint: Color { ThemeManager.shared.theme.palette.tint }

    /// Muted text that sits DIRECTLY on the page background (List section
    /// headers, panel labels, helper captions under the bottom CTA).
    /// System `.secondary` stays gray regardless of theme and disappears
    /// against the dark felt/walnut pages, so page-level muted text uses
    /// this espresso-derived tone instead — it tracks each theme's ink and
    /// reads on every page color. Text inside cards keeps `.secondary`.
    static var paperSecondary: Color { espressoInk.opacity(0.72) }
}

/// Convenience enum accessor over `AppSettings.appTheme`'s raw storage —
/// mirrors `AnnouncerVoice`/`AnnouncerStyle`'s accessor pattern in
/// `Announcer.swift`. Defined here (App layer) rather than in
/// `Models/AppSettings.swift` so the Models layer never has to import an
/// App-layer enum.
extension AppSettings {
    var appThemeSelection: AppTheme {
        get { AppTheme(rawValue: appTheme) ?? .parchment }
        set { appTheme = newValue.rawValue }
    }
}

/// The full page-background treatment: `paperBase` plus, in light mode
/// only, the active theme's tiled paper-grain texture (opacity from
/// `ThemePalette.grainOpacity`, multiply blend) over it — skipped entirely
/// when the active theme's `showGrain` is `false` (Card Table's felt
/// background). Dark mode renders as a flat `paperBase` fill only. Never
/// touches cards, rows, chips, or type — see `View.paperBackground()`.
struct PaperBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let palette = themeManager.theme.palette
        ZStack {
            Color.paperBase
            if colorScheme == .light && palette.showGrain {
                Image("PaperGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(palette.grainOpacity)
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

/// Quick light/dark toggle for the scoreboard toolbar — dark mode saves
/// battery on OLED phones during long game nights. Writes through to the
/// persisted `AppSettings.appearance` (which `RootView` applies globally),
/// so the choice sticks and the Settings picker stays in sync. From
/// `.system` it jumps to the opposite of the current effective scheme.
struct AppearanceToggleButton: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: toggle) {
            Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
        }
        .accessibilityLabel(colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode")
    }

    private func toggle() {
        guard let settings = try? AppSettings.fetchOrCreate(in: modelContext) else { return }
        settings.appearance = colorScheme == .dark ? .light : .dark
        modelContext.saveNow()
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
                    .foregroundStyle(Color.appTint)
            }
            Text(title)
                .font(.system(size: titleSize * titleScale / 100, weight: .heavy))
                .foregroundStyle(Color.espressoInk)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: subtitleSize, weight: .medium))
                    .foregroundStyle(Color.paperSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        // 4pt (not 2) top/bottom: rounded letterforms (R, D, O, C…) draw
        // with a slight optical overshoot past their cap-height/baseline,
        // and this block sits inside a zero-inset List row (see call
        // sites' `.listRowInsets(EdgeInsets())`). With only 2pt of
        // clearance the row's tight clip bounds sliced off that overshoot
        // on the very first/last line — reported as the eyebrow's "R" and
        // a trailing subtitle's "D" getting clipped at a corner. 4pt gives
        // the overshoot room without visibly changing the block's rhythm.
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}

/// Full-width 50pt CTA button matching the mockup's `.btn`: indigo fill,
/// 14pt corner radius, 17pt bold white label. `isDisabled` maps to the
/// mockup's `.btn.disabled`: a warm `Color.warmDisabled` fill (see its doc
/// comment) with tertiary-label text, and disables interaction.
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
        .background(isDisabled ? Color.warmDisabled : Color.feltGreen)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(isDisabled)
    }
}

/// Full-width 50pt hero CTA for the Trends section's single table-wide
/// broadcast, shared by `GameView` (iPhone) and `ScorepadGridView` (iPad) so
/// both platforms get an identical hero treatment: brassGold fill (distinct
/// from `PrimaryActionButton`'s feltGreen Enter Round CTA), 14pt corner
/// radius, white bold label with a speaker/stop icon. While idle, a gentle
/// repeating "breathing" glow (brassGold shadow opacity 0.25→0.6 plus a
/// hair of scale, 1.0→1.02) nudges the dealer to press it — subtle and
/// classy, not a strobe. The pulse stops the instant playback starts and
/// never runs at all when Reduce Motion is on.
struct AnnounceHeroButton: View {
    var isPlaying: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseUp = false
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17

    /// Only breathe while idle and only when the system isn't asking for
    /// reduced motion.
    private var pulsing: Bool { !isPlaying && !reduceMotion }

    var body: some View {
        Button(action: action) {
            Label(
                isPlaying ? "Stop" : "Play Round Commentary",
                systemImage: isPlaying ? "stop.fill" : "speaker.wave.2.fill"
            )
            .font(.system(size: titleSize, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .foregroundStyle(.white)
        .background(Color.brassGold)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(
            color: Color.brassGold.opacity(pulsing ? (pulseUp ? 0.6 : 0.25) : 0),
            radius: pulsing && pulseUp ? 16 : 6
        )
        .scaleEffect(pulsing && pulseUp ? 1.02 : 1.0)
        .onAppear { syncPulse() }
        .onChange(of: pulsing) { _, _ in syncPulse() }
    }

    /// Starts (or stops) the repeating breathing animation to match
    /// `pulsing`'s current value — called on appear and whenever `isPlaying`
    /// or Reduce Motion flips.
    private func syncPulse() {
        if pulsing {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulseUp = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                pulseUp = false
            }
        }
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
