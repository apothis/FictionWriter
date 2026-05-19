import Foundation

/// AO3-style work framing — the author's declared stance toward the
/// dark/heavy content the work contains.
///
/// The fanfic-community "Dead Dove: Do Not Eat" convention signals
/// *no authorial subversion* — the dark thing is depicted directly,
/// not undercut, redeemed, or moralised. That stance is a craft
/// commitment, and it is also generation-relevant: a `playedStraight`
/// element feeds an anti-softening clause so the model doesn't quietly
/// redeem or moralise content the author chose deliberately.
public struct FramedElement: Codable, Equatable {
    /// Free-form content element — e.g. "non-consent", "graphic
    /// violence", "a morally irredeemable protagonist".
    public var name: String
    public var stance: ContentStance

    public init(name: String, stance: ContentStance = .playedStraight) {
        self.name = name
        self.stance = stance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.stance = try c.decodeIfPresent(ContentStance.self, forKey: .stance) ?? .playedStraight
    }
}

public enum ContentStance: String, Codable, Equatable, CaseIterable {
    /// Dead Dove — depicted directly; not subverted, redeemed, or
    /// moralised. The only stance that feeds a prompt clause.
    case playedStraight
    /// Set up, then deliberately undercut or redeemed by the narrative.
    case subverted
    /// Present, but the narrative frames it as wrong.
    case critiqued
}
