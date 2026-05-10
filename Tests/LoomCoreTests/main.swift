import Foundation

let suites: [TestSuite] = [
    phase1DebugLogTests(),
    phase1ProjectCodableTests(),
    phase1SceneFrontmatterTests(),
    phase1ProjectStorageTests(),
    phase1SchemaVersionTests(),
    phase1ServerProbeParseTests(),
    phase1KoboldClientRegistryTests(),
    phase1AppSettingsCodableTests(),
    phase1KoboldClientSmokeTests(),
    phase1DesignTokensTests(),
    phase1SceneListOperationsTests(),
    phase1ProjectSessionTests(),
    phase1SidebarMountTests(),
    phase1EditorWordCountTests(),
    phase1ProjectSessionSelectionTests(),
    phase1CharacterAddTests(),
    phase1InspectorTabPersistenceTests(),
    phase1GenerationModeAvailabilityTests(),
    phase1InstructTemplateTests(),
    phase1RecentProseWindowTests(),
    phase1PromptBuilderLayersTests(),
    phase1PersistedSessionTests(),
    phase1AcceptanceStateTests(),
    phase1HistoryLogReadWriteTests(),
    phase1HistoryExpansionTests(),
]

// `TestRunner.run` is `@MainActor`-isolated so test bodies can drive
// MainActor-bound types. Top-level main.swift code isn't actor-isolated
// by default, but executables run their main on the main thread, so
// `assumeIsolated` is the right hop.
exit(MainActor.assumeIsolated { TestRunner.run(suites) })
