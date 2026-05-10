import Foundation
@testable import LoomCore

/// Sub-step 1.m — recent-projects list (capped at 5; dedupe-on-push).
/// Lives on AppSettings so it persists across launches via the same
/// settings.json the server profiles do.
func phase1RecentProjectsTests() -> TestSuite {
    let s = TestSuite("Phase1RecentProjects")

    s.test("pushing a URL adds it to the front of the list") {
        var settings = AppSettings.defaults
        let url = URL(fileURLWithPath: "/tmp/A.loom")
        settings.pushRecentProject(url)
        try expectEqual(settings.recentProjectURLs, [url])
    }

    s.test("pushing the same URL again moves it to front, no duplicate") {
        var settings = AppSettings.defaults
        let a = URL(fileURLWithPath: "/tmp/A.loom")
        let b = URL(fileURLWithPath: "/tmp/B.loom")
        settings.pushRecentProject(a)
        settings.pushRecentProject(b)
        settings.pushRecentProject(a)
        try expectEqual(settings.recentProjectURLs, [a, b])
    }

    s.test("list is capped at 5 entries; oldest dropped") {
        var settings = AppSettings.defaults
        for i in 1...7 {
            settings.pushRecentProject(URL(fileURLWithPath: "/tmp/Project\(i).loom"))
        }
        try expectEqual(settings.recentProjectURLs.count, 5)
        // First entry should be the most-recently-pushed (Project7);
        // last should be Project3 (Project1 + Project2 evicted).
        try expectEqual(settings.recentProjectURLs.first?.lastPathComponent, "Project7.loom")
        try expectEqual(settings.recentProjectURLs.last?.lastPathComponent, "Project3.loom")
    }

    s.test("AppSettings round-trips recentProjectURLs") {
        var settings = AppSettings.defaults
        settings.pushRecentProject(URL(fileURLWithPath: "/tmp/A.loom"))
        settings.pushRecentProject(URL(fileURLWithPath: "/tmp/B.loom"))
        let data = try JSONEncoder.loomPretty.encode(settings)
        let decoded = try JSONDecoder.loom.decode(AppSettings.self, from: data)
        try expectEqual(decoded.recentProjectURLs, settings.recentProjectURLs)
    }

    return s
}
