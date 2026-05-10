import Foundation

/// Pure data-shape rule for "should the editor show the empty-project
/// placeholder vs the live text view?". Per LOOM_DESIGN_LANGUAGE.md
/// §14.7: the empty state replaces the editor when the project has
/// no scenes (or no current scene selection — e.g. after the only
/// scene was moved to trash).
public enum EmptyProjectState {
    public static func shouldShow(in session: ProjectSession) -> Bool {
        if session.project.manuscript.orphanedSceneIds.isEmpty {
            return true
        }
        if session.currentSceneId == nil {
            return true
        }
        return false
    }
}
