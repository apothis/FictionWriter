import Foundation

let suites: [TestSuite] = [
    phase1DebugLogTests(),
]

// `TestRunner.run` is `@MainActor`-isolated so test bodies can drive
// MainActor-bound types. Top-level main.swift code isn't actor-isolated
// by default, but executables run their main on the main thread, so
// `assumeIsolated` is the right hop.
exit(MainActor.assumeIsolated { TestRunner.run(suites) })
