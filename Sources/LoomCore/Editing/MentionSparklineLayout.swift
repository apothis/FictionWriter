import Foundation

/// Phase 2.5 (#11 follow-on) — pure-data layout for the per-entity
/// mention sparkline. Given a scene-id ordering + a per-scene
/// mention count, computes the marker positions the sparkline view
/// renders. Hit-test routes a click back to the originating scene
/// id so the editor can `selectScene(id:)`.
///
/// The rendering surface (`MentionSparklineView`) consumes this
/// layout directly; tests pin geometry + hit-testing here so the
/// view stays a thin draw + click forwarder.
public struct MentionSparklineLayout: Equatable {
    public struct Marker: Equatable {
        public let sceneId: UUID
        /// Position along the bar, in [0, 1]. View multiplies by
        /// available width.
        public let xRatio: Double
        public let count: Int
    }

    public let markers: [Marker]
    public let totalScenes: Int

    public static func build(
        sceneOrder: [UUID],
        mentionsBySceneId: [UUID: Int]
    ) -> MentionSparklineLayout {
        let total = sceneOrder.count
        guard total > 0 else { return MentionSparklineLayout(markers: [], totalScenes: 0) }
        let slot = 1.0 / Double(total)
        var markers: [Marker] = []
        for (i, id) in sceneOrder.enumerated() {
            let count = mentionsBySceneId[id] ?? 0
            guard count > 0 else { continue }
            // Centre of the i-th slot.
            let xRatio = (Double(i) + 0.5) * slot
            markers.append(Marker(sceneId: id, xRatio: xRatio, count: count))
        }
        return MentionSparklineLayout(markers: markers, totalScenes: total)
    }

    /// Returns the marker whose `xRatio` is within `tolerance` of
    /// `xRatio`, or nil if none is close enough. Used by the view's
    /// `mouseDown(with:)` hit-test.
    public func hitTest(xRatio: Double, tolerance: Double) -> Marker? {
        var best: (Marker, Double)? = nil
        for m in markers {
            let d = abs(m.xRatio - xRatio)
            if d <= tolerance {
                if best == nil || d < best!.1 {
                    best = (m, d)
                }
            }
        }
        return best?.0
    }
}
