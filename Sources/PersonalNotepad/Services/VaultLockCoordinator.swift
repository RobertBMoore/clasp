import AppKit
import Foundation

@MainActor
final class VaultLockCoordinator {
    static let shared = VaultLockCoordinator()
    var lockHandler: (() -> Void)?
    var terminationHandler: (() async -> Void)?

    private var timer: Timer?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    init() {}

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockNow() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockNow() }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockNow() }
        })
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.noteActivity() }
            return event
        }
        noteActivity()
    }

    func noteActivity() {
        timer?.invalidate()
        let raw = UserDefaults.standard.string(forKey: PreferenceKeys.autoLockTimeout)
            ?? VaultAutoLockTimeout.tenMinutes.rawValue
        guard let interval = (VaultAutoLockTimeout(rawValue: raw) ?? .tenMinutes).duration else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockNow() }
        }
    }

    func lockNow() {
        timer?.invalidate()
        lockHandler?()
    }

    func flushAndLockForTermination() async {
        timer?.invalidate()
        if let terminationHandler { await terminationHandler() }
        else { lockHandler?() }
    }
}
