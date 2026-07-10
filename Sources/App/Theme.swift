import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.indigo)
            }
            Text(title)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
                .font(.system(size: 22, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(dimmed ? Color(.tertiaryLabel) : .primary)
                .frame(minWidth: 28, alignment: .center)

            HStack(spacing: 0) {
                stepButton(systemName: "minus", enabled: minusEnabled, action: onMinus)
                Rectangle()
                    .fill(Color.indigo.opacity(0.28))
                    .frame(width: 1, height: 32)
                stepButton(systemName: "plus", enabled: plusEnabled, action: onPlus)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.indigo.opacity(0.12))
                    .frame(height: 32)
            )
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // The frame + contentShape live INSIDE the button label so the
            // full 38×44 area is genuinely tappable — applied outside the
            // Button they'd only pad layout, not the hit target.
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.indigo)
                .frame(width: 38, height: 44)
                .contentShape(Rectangle())
        }
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}
