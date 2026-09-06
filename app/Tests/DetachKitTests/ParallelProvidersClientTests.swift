import XCTest
@testable import DetachKit

final class ParallelProvidersClientTests: XCTestCase {
    func testErrorDescriptionsCoverTimeoutCommandAndEmptyResponse() {
        XCTAssertEqual(
            ParallelProvidersClientError.timedOut.errorDescription,
            L10n.string("detach config timed out"))
        XCTAssertEqual(
            ParallelProvidersClientError.commandFailed("denied").errorDescription,
            "denied")
        XCTAssertEqual(
            ParallelProvidersClientError.invalidResponse("").errorDescription,
            L10n.format(
                "detach returned an unsupported parallel-providers setting: %@",
                L10n.string("<empty>")))
        XCTAssertEqual(
            ParallelProvidersClientError.invalidResponse("always").errorDescription,
            L10n.format(
                "detach returned an unsupported parallel-providers setting: %@",
                "always"))
    }

    func testLoadsSettingThroughConfigGetter() async throws {
        let cli = FakeCLI()
        cli.responses["config parallel-providers"] = .success(CLIResult(
            exitCode: 0, stdout: "off\n", stderr: "", timedOut: false))

        let setting = try await ParallelProvidersClient(cli: cli).loadSetting()

        XCTAssertEqual(setting, .off)
        XCTAssertFalse(setting.isEnabled)
        XCTAssertEqual(cli.calls, [["config", "parallel-providers"]])
    }

    func testSavesSettingThroughConfigSetter() async throws {
        let cli = FakeCLI()

        try await ParallelProvidersClient(cli: cli).setSetting(.on)

        XCTAssertEqual(cli.calls, [["config", "parallel-providers", "on"]])
    }

    func testRejectsUnsupportedGetterOutput() async {
        let cli = FakeCLI()
        cli.responses["config parallel-providers"] = .success(CLIResult(
            exitCode: 0, stdout: "always\n", stderr: "", timedOut: false))

        do {
            _ = try await ParallelProvidersClient(cli: cli).loadSetting()
            XCTFail("expected invalid response")
        } catch {
            XCTAssertEqual(
                error as? ParallelProvidersClientError,
                .invalidResponse("always"))
        }
    }

    func testReportsCLIErrorTimeoutAndMissingStderr() async {
        let failing = FakeCLI()
        failing.responses["config parallel-providers off"] = .success(CLIResult(
            exitCode: 2, stdout: "", stderr: "config is read-only\n", timedOut: false))
        do {
            try await ParallelProvidersClient(cli: failing).setSetting(.off)
            XCTFail("expected command failure")
        } catch {
            XCTAssertEqual(
                error as? ParallelProvidersClientError,
                .commandFailed("config is read-only"))
        }

        let timedOut = FakeCLI()
        timedOut.responses["config parallel-providers"] = .success(CLIResult(
            exitCode: 15, stdout: "", stderr: "", timedOut: true))
        do {
            _ = try await ParallelProvidersClient(cli: timedOut).loadSetting()
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? ParallelProvidersClientError, .timedOut)
        }

        let missingStderr = FakeCLI()
        missingStderr.responses["config parallel-providers on"] = .success(CLIResult(
            exitCode: 23, stdout: "", stderr: " \n", timedOut: false))
        do {
            try await ParallelProvidersClient(cli: missingStderr).setSetting(.on)
            XCTFail("expected command failure")
        } catch {
            XCTAssertEqual(
                error as? ParallelProvidersClientError,
                .commandFailed(L10n.format("detach config exited with status %d", 23)))
        }
    }
}
