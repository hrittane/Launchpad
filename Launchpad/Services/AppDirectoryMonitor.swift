import AppKit
import Foundation

/// Watches the application folders through Spotlight and coalesces bursts of
/// changes into one rescan request. The actual scan is always performed by
/// `AppScanner`; this type only decides *when* to scan.
@MainActor
final class AppDirectoryMonitor {
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>?
    private var onChange: (() -> Void)?
    private var isRunning = false

    func start(roots: [URL], onChange: @escaping () -> Void) {
        guard !isRunning else { return }
        self.onChange = onChange
        isRunning = true

        query.predicate = NSPredicate(
            format: "kMDItemContentType == %@",
            "com.apple.application-bundle"
        )
        query.searchScopes = roots
        query.notificationBatchingInterval = 1.0

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRescan() }
        })
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRescan() }
        })

        query.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        debounceTask?.cancel()
        debounceTask = nil
        query.stop()
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    private func scheduleRescan() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
