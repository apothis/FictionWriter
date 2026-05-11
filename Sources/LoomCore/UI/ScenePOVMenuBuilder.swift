import Foundation

/// Phase 4 #7 adjacent — pure-data descriptor list for the sidebar's
/// "Set POV" submenu. Kept Foundation-only so the menu shape can be
/// pinned in tests without an AppKit dependency; the sidebar glue
/// translates these descriptors into `NSMenuItem`s + sets `.state`
/// from `isCurrent`.
public struct ScenePOVMenuDescriptor: Equatable {
    /// Human-readable label (`"Clear POV"` or the character's `name`).
    public let title: String
    /// Target POV value when the user picks this row. `nil` clears.
    public let characterId: UUID?
    /// Whether this descriptor represents the scene's current POV
    /// selection (drives the menu-item checkmark).
    public let isCurrent: Bool
}

public enum ScenePOVMenuBuilder {
    /// Builds the "Set POV" submenu descriptors. Layout:
    /// 1. Leading "Clear POV" row that maps to `nil` (always present).
    /// 2. One row per bible character, in input order.
    ///
    /// The descriptor matching `currentPOV` (or "Clear POV" when
    /// `currentPOV == nil`) carries `isCurrent = true`. If
    /// `currentPOV` is non-nil but matches no character (stale id),
    /// every descriptor is non-current.
    public static func menuItems(
        characters: [Character],
        currentPOV: UUID?
    ) -> [ScenePOVMenuDescriptor] {
        var items: [ScenePOVMenuDescriptor] = [
            ScenePOVMenuDescriptor(
                title: "Clear POV",
                characterId: nil,
                isCurrent: currentPOV == nil
            )
        ]
        for character in characters {
            items.append(ScenePOVMenuDescriptor(
                title: character.name,
                characterId: character.id,
                isCurrent: character.id == currentPOV
            ))
        }
        return items
    }
}
