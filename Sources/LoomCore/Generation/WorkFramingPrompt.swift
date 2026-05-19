import Foundation

/// Turns a project's `workFraming` into a system-prompt clause.
///
/// Only `playedStraight` elements produce text — they are the ones the
/// model needs told, so it doesn't quietly subvert, redeem, or
/// moralise content the author chose deliberately (the "Dead Dove"
/// stance). `subverted` / `critiqued` elements are the author's own
/// craft business and need no instruction.
public enum WorkFramingPrompt {

    public static func systemAddendum(_ elements: [FramedElement]) -> String {
        let straight = elements
            .filter { $0.stance == .playedStraight }
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !straight.isEmpty else { return "" }
        return "\n\nThis work depicts the following directly and without "
            + "subversion, redemption arc, or narrative moralising — render "
            + "them straight, as the author intends: "
            + straight.joined(separator: "; ") + "."
    }
}
