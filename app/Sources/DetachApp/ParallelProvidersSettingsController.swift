import DetachKit
import Foundation

/// Loads and persists the opt-in project collaboration setting for Settings → General.
@MainActor
final class ParallelProvidersSettingsController: ObservableObject {
    @Published private(set) var setting: ParallelProviders?
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    private let makeClient: (String) -> ParallelProvidersClient
    private var activePath: String?

    init(
        makeClient: @escaping (String) -> ParallelProvidersClient = { path in
            ParallelProvidersClient(
                cli: ProcessDetachCLI(executable: URL(fileURLWithPath: path)))
        }
    ) {
        self.makeClient = makeClient
    }

    var isEnabled: Bool { setting?.isEnabled ?? false }

    func load(detachPath: String) async {
        activePath = detachPath
        isUpdating = true
        errorMessage = nil
        defer {
            if activePath == detachPath {
                isUpdating = false
            }
        }
        do {
            let value = try await makeClient(detachPath).loadSetting()
            guard !Task.isCancelled, activePath == detachPath else { return }
            setting = value
        } catch {
            guard !Task.isCancelled, activePath == detachPath else { return }
            setting = nil
            errorMessage = L10n.format(
                "Couldn't read the parallel agents setting: %@",
                error.localizedDescription)
        }
    }

    func save(_ newValue: ParallelProviders, detachPath: String) async {
        guard !isUpdating, let previous = setting, newValue != previous else { return }
        activePath = detachPath
        setting = newValue
        isUpdating = true
        errorMessage = nil
        defer {
            if activePath == detachPath {
                isUpdating = false
            }
        }
        do {
            try await makeClient(detachPath).setSetting(newValue)
        } catch {
            guard !Task.isCancelled, activePath == detachPath else { return }
            setting = previous
            errorMessage = L10n.format(
                "Couldn't save the parallel agents setting: %@",
                error.localizedDescription)
        }
    }
}
