import Foundation
import Testing
import WASTRunner
@_spi(Fuzzing) import WasmKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRABRIX_RUN_EXPERIMENTAL_DIRECT"] == "1"))
struct ExperimentalDirectSpecTests {
    @Test func coreAndCompilerInstructionRegressionsUseSoftwareBounds() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scripts = try SpectestDiscovery(path: [
            root.appendingPathComponent("Vendor/testsuite").path,
            root.appendingPathComponent("Tests/WasmKitTests/ExtraSuite").path,
            root.appendingPathComponent("Tests/WasmKitTests/ExtraSuite/fuel").path,
        ]).discover()
        #expect(scripts.count > 100)
        var configuration = EngineConfiguration(threadingModel: .direct,
            memoryBoundsChecking: .software, fuelMetering: true)
        configuration.enableExperimentalSoftwareDirectThreading()
        let runner = try SpectestRunner(configuration: configuration)
        for script in scripts {
            try runner.run(test: script, reporter: NullSpectestProgressReporter())
        }
        print("EXPERIMENTAL_DIRECT_SOFTWARE_SCRIPTS", scripts.count)
    }
}
