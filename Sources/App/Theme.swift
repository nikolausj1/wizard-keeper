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
