import DetachKit
import Foundation
import XCTest
@testable import DetachApp

private final class ParallelProvidersScriptedCLI: DetachCLIRunning, @unchecked Sendable {
    var responses: [String: Result<CLIResult, Error>] = [:]
    private(set) var calls: [[String]] = []

    func run(arguments: [String], timeout: TimeInterval) async throws -> CLIResult {
        calls.append(arguments)
        let key = arguments.joined(separator: " ")
        if let response = responses[key] {
            return try response.get()
        }
        return CLIResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
    }
}

@MainActor
final class ParallelProvidersSettingsControllerTests: XCTestCase {
    private func controller(
        _ cli: ParallelProvidersScriptedCLI
    ) -> ParallelProvidersSettingsController {
        ParallelProvidersSettingsController(
            makeClient: { _ in ParallelProvidersClient(cli: cli) })
    }

    func testLoadPublishesSettingAndClearsUpdating() async {
        let cli = ParallelProvidersScriptedCLI()
        cli.responses["config parallel-providers"] = .success(CLIResult(
            exitCode: 0, stdout: "off\n", stderr: "", timedOut: false))
        let sut = controller(cli)

        await sut.load(detachPath: "/opt/detach")

        XCTAssertEqual(sut.setting, .off)
        XCTAssertFalse(sut.isEnabled)
        XCTAssertFalse(sut.isUpdating)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(cli.calls, [["config", "parallel-providers"]])
    }

    func testLoadFailureReportsErrorAndClearsSetting() async {
        let cli = ParallelProvidersScriptedCLI()
        cli.responses["config parallel-providers"] = .success(CLIResult(
            exitCode: 3, stdout: "", stderr: "boom\n", timedOut: false))
        let sut = controller(cli)

        await sut.load(detachPath: "/opt/detach")

        XCTAssertNil(sut.setting)
        XCTAssertEqual(
            sut.errorMessage,
            L10n.format("Couldn't read the parallel agents setting: %@", "boom"))
    }

    func testSaveSendsSetterAndKeepsValue() async {
        let cli = ParallelProvidersScriptedCLI()
        cli.responses["config parallel-providers"] = .success(CLIResult(
            exitCode: 0, stdout: "off\n", stderr: "", timedOut: false))
        let sut = controller(cli)
        await sut.load(detachPath: "/opt/detach")

        await sut.save(.on, detachPath: "/opt/detach")

        XCTAssertEqual(sut.setting, .on)
        XCTAssertTrue(sut.isEnabled)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(cli.calls.last, ["config", "parallel-providers", "on"])
    }

    func testSaveFailureRollsBackToPreviousValue() async {
        let cli = ParallelProvidersScriptedCLI()
        cli.responses["config parallel-providers"] = .success(CLIResult(
            exitCode: 0, stdout: "on\n", stderr: "", timedOut: false))
        cli.responses["config parallel-providers off"] = .success(CLIResult(
            exitCode: 5, stdout: "", stderr: "locked\n", timedOut: false))
        let sut = controller(cli)
        await sut.load(detachPath: "/opt/detach")

        await sut.save(.off, detachPath: "/opt/detach")

        XCTAssertEqual(sut.setting, .on)
        XCTAssertEqual(
            sut.errorMessage,
            L10n.format("Couldn't save the parallel agents setting: %@", "locked"))
    }

    func testDefaultClientReadsThroughARealDetachExecutable() async throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-detach-\(UUID().uuidString)")
        try "#!/bin/sh\nprintf 'off\\n'\n".write(
            to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }

        let sut = ParallelProvidersSettingsController()
        await sut.load(detachPath: script.path)

        XCTAssertEqual(sut.setting, .off)
        XCTAssertNil(sut.errorMessage)
    }

    func testSaveIgnoresNoOpAndUnloadedState() async {
        let cli = ParallelProvidersScriptedCLI()
        let sut = controller(cli)

        await sut.save(.on, detachPath: "/opt/detach")
        XCTAssertTrue(cli.calls.isEmpty)

        cli.responses["config parallel-providers"] = .success(CLIResult(
            exitCode: 0, stdout: "on\n", stderr: "", timedOut: false))
        await sut.load(detachPath: "/opt/detach")
        let callsAfterLoad = cli.calls.count

        await sut.save(.on, detachPath: "/opt/detach")
        XCTAssertEqual(cli.calls.count, callsAfterLoad)
    }
}
