import Foundation
import SwiftData

/// A player profile that can be seated in games.
///
/// Invariant: `Player` stores only identity data (name, color, creation
/// date) — never scores or history. Lifetime statistics (games played,
/// wins, average score, etc.) are always derived on demand by scanning
/// completed `Game` records elsewhere, so a player's stats can never drift
/// out of sync with actual game history.
@Model
final class Player {
    /// Stable identity for this player. Referenced by `Participant` and
    /// `RoundEntry` snapshots across games, so it must never change once
    /// assigned.
    @Attribute(.unique) var id: UUID

    /// Display name shown in the UI. Renaming a player does not affect
    /// past games, which retain their own frozen `displayNameSnapshot`.
    var name: String

    /// Index into a fixed 8-color palette owned by the UI layer. Stored as
    /// a plain `Int` so the persistence layer has no dependency on
    /// SwiftUI/color types.
    var colorId: Int

    /// When this player profile was created.
    var createdAt: Date

    init(id: UUID = UUID(), name: String, colorId: Int, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorId = colorId
        self.createdAt = createdAt
    }
}
