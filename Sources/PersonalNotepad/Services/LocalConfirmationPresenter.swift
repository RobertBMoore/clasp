import AppKit
import SwiftUI

enum LocalConfirmationKind {
    case success
    case information
    case warning
    case error

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: .green
        case .information: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}

@MainActor
final class LocalConfirmationPresenter {
    static let shared = LocalConfirmationPresenter()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String, kind: LocalConfirmationKind = .success) {
        let allowedBundleIDs = [
            "com.robertmoore.personalnotepad",
            "com.robertmoore.personalnotepad.visualqa"
        ]
        guard let bundleID = Bundle.main.bundleIdentifier,
              allowedBundleIDs.contains(bundleID) else { return }

        announce(message)
        // A foreground SwiftUI window owns its inline status or alert. The
        // floating panel is reserved for Dock, menu-bar, Service, and hotkey
        // actions that otherwise have no visible response surface.
        if NSApp.isActive && NSApp.keyWindow?.isVisible == true {
            dismissTask?.cancel()
            dismissTask = nil
            panel?.orderOut(nil)
            return
        }
        dismissTask?.cancel()

        let content = LocalConfirmationView(message: message, kind: kind)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 380, height: 74)

        let panel = panel ?? makePanel()
        panel.setContentSize(host.frame.size)
        panel.contentView = host
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: kind == .error ? .seconds(5) : .seconds(3))
            guard !Task.isCancelled, let panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    self?.dismissTask = nil
                }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 54),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        return panel
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func position(_ panel: NSPanel) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 20, y: frame.maxY - panel.frame.height - 20))
    }
}

private struct LocalConfirmationView: View {
    let message: String
    let kind: LocalConfirmationKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
            Text(message)
                .font(.callout.weight(.medium))
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 380, height: 74)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.45)))
    }
}
