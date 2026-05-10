import Foundation
@testable import LoomCore

/// Sub-step 1.e — pure-data tests for the reorder/delete primitives that
/// SidebarController calls on each user action. Centralised in
/// SceneListOperations so the test surface is a flat array of UUIDs and
/// the tests don't require any AppKit machinery.
///
/// Per the LOOM_PHASE1_EDITOR_MVP.md §4.1.e contract: "pure-data: reorder
/// operations on [UUID] produce expected sequences."
func phase1SceneListOperationsTests() -> TestSuite {
    let s = TestSuite("Phase1SceneListOperations")

    s.test("move forward shifts the element to the new index") {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let result = SceneListOperations.move([a, b, c, d], from: 1, to: 3)
        try expectEqual(result, [a, c, d, b])
    }

    s.test("move backward shifts the element to the new index") {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let result = SceneListOperations.move([a, b, c, d], from: 2, to: 0)
        try expectEqual(result, [c, a, b, d])
    }

    s.test("move to same index is identity") {
        let a = UUID(), b = UUID(), c = UUID()
        let original = [a, b, c]
        try expectEqual(SceneListOperations.move(original, from: 1, to: 1), original)
    }

    s.test("move with out-of-range indices is identity") {
        let a = UUID(), b = UUID(), c = UUID()
        let original = [a, b, c]
        try expectEqual(SceneListOperations.move(original, from: -1, to: 0), original)
        try expectEqual(SceneListOperations.move(original, from: 0, to: 99), original)
    }

    s.test("delete removes the matching id and preserves order") {
        let a = UUID(), b = UUID(), c = UUID()
        try expectEqual(SceneListOperations.delete(b, from: [a, b, c]), [a, c])
    }

    s.test("delete of an absent id is identity") {
        let a = UUID(), b = UUID()
        let absent = UUID()
        try expectEqual(SceneListOperations.delete(absent, from: [a, b]), [a, b])
    }

    s.test("insert at end appends; insert at 0 prepends") {
        let a = UUID(), b = UUID(), c = UUID()
        try expectEqual(SceneListOperations.insert(c, at: 2, into: [a, b]), [a, b, c])
        try expectEqual(SceneListOperations.insert(c, at: 0, into: [a, b]), [c, a, b])
    }

    s.test("insert clamps out-of-range indices into [0, count]") {
        let a = UUID(), b = UUID(), x = UUID()
        try expectEqual(SceneListOperations.insert(x, at: -5, into: [a, b]), [x, a, b])
        try expectEqual(SceneListOperations.insert(x, at: 999, into: [a, b]), [a, b, x])
    }

    return s
}
