import Foundation

public enum ParallelProviders: String, Equatable, Sendable, CaseIterable {
    /// Allow one Codex and one Claude Code session in the same canonical project.
    case on
    /// Keep the default single managed writer for each canonical project.
    case off

    public var isEnabled: Bool { self == .on }
}

public enum ParallelProvidersClientError: LocalizedError, Equatable {
    case timedOut
    case commandFailed(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            L10n.string("detach config timed out")
        case .commandFailed(let message):
            message
        case .invalidResponse(let value):
            L10n.format(
                "detach returned an unsupported parallel-providers setting: %@",
                value.isEmpty ? L10n.string("<empty>") : value)
        }
    }
}

/// Typed access to the CLI-backed cross-provider project concurrency setting.
public struct ParallelProvidersClient: Sendable {
    private let cli: any DetachCLIRunning

    public init(cli: any DetachCLIRunning) {
        self.cli = cli
    }

    public func loadSetting() async throws -> ParallelProviders {
        let result = try await cli.run(arguments: ["config", "parallel-providers"], timeout: 5)
        try validate(result)
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let setting = ParallelProviders(rawValue: value) else {
            throw ParallelProvidersClientError.invalidResponse(value)
        }
        return setting
    }

    public func setSetting(_ setting: ParallelProviders) async throws {
        let result = try await cli.run(
            arguments: ["config", "parallel-providers", setting.rawValue],
            timeout: 5)
        try validate(result)
    }

    private func validate(_ result: CLIResult) throws {
        if result.timedOut {
            throw ParallelProvidersClientError.timedOut
        }
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ParallelProvidersClientError.commandFailed(
                stderr.isEmpty
                    ? L10n.format("detach config exited with status %d", result.exitCode)
                    : stderr)
        }
    }
}
