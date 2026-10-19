import AppKit
import Observation
import SwiftUI

/// Menu bar item + non-activating popover panel.
///
/// Ported from the reference app's pattern, which exists because `MenuBarExtra`
/// cannot produce the rounded glass panel this design calls for: an `NSPanel` is
/// positioned under the status item, hosts an `NSHostingController`, and dismisses on
/// Esc or on a click outside either the panel or the button.
@MainActor
final class StatusBarController: NSObject {

    private let store: ConfigurationStore
    private let hostingController: NSHostingController<AnyView>
    private let panel: StatusBarPanel
    private let backgroundView = StatusBarBackgroundView()

    private var statusItem: NSStatusItem?
    /// `Any?` holds an opaque `NSEvent` monitor token, which is not `Sendable`.
    /// Marked `nonisolated(unsafe)` so `deinit` can remove them; they are only ever
    /// touched on the main actor otherwise, and this object lives for the app's
    /// lifetime anyway.
    nonisolated(unsafe) private var localEventMonitor: Any?
    nonisolated(unsafe) private var globalEventMonitor: Any?

    private static let panelWidth: CGFloat = 320
    private static let symbolConnected = "computermouse"
    private static let symbolDisconnected = "computermouse.slash"

    var isInserted: Bool { statusItem != nil }

    init(store: ConfigurationStore) {
        self.store = store
        self.hostingController = NSHostingController(
            rootView: AnyView(BarView().environment(store))
        )
        self.panel = StatusBarPanel()
        super.init()

        configurePanel()
        configureEventMonitors()
        observeStore()
    }

    /// Re-arm an observation chain whenever relevant store state changes, so the
    /// menu bar symbol follows connection state without polling.
    private func observeStore() {
        withObservationTracking {
            _ = store.phase
            _ = store.devices.map { $0.connected.value }
            _ = store.selectedDeviceID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusImage()
                self.observeStore()
            }
        }
    }

    deinit {
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
    }

    func insert() {
        guard statusItem == nil else { updateStatusImage(); return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "SteelSeries Config"
        statusItem = item
        updateStatusImage()
    }

    func showPopover() {
        guard statusItem?.button != nil else { return }
        updatePanelFrame()
        guard !panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    func closePopover() {
        panel.orderOut(nil)
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        if panel.isVisible {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func configurePanel() {
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = [.preferredContentSize]
        }

        panel.onEscape = { [weak self] in self?.closePopover() }
        panel.contentView = backgroundView

        backgroundView.contentView.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.setContentHuggingPriority(.required, for: .vertical)
        hostingController.view.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: backgroundView.contentView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: backgroundView.contentView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: backgroundView.contentView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: backgroundView.contentView.bottomAnchor),
        ])
    }

    private func configureEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53, panel.isVisible {
                closePopover()
                return nil
            }

            guard panel.isVisible else { return event }
            if shouldClose(for: event) { closePopover() }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, panel.isVisible else { return }
            if shouldClose(for: event) { closePopover() }
        }
    }

    private func shouldClose(for event: NSEvent) -> Bool {
        let point = screenLocation(for: event)
        return !panel.frame.contains(point) && !statusItemFrame.contains(point)
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        let inWindow = window.convertPoint(toScreen: event.locationInWindow)
        return inWindow
    }

    private var statusItemFrame: NSRect {
        guard let button = statusItem?.button, let window = button.window else { return .zero }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    private func updatePanelFrame() {
        guard let button = statusItem?.button else { return }

        hostingController.view.layoutSubtreeIfNeeded()

        let fitting = hostingController.view.fittingSize
        let contentSize = NSSize(width: Self.panelWidth, height: max(fitting.height, 80))
        panel.setContentSize(contentSize)

        let buttonFrame = statusItemFrame
        let screenFrame = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // Clamp inside the screen and hang just below the status item, matching the
        // reference app's anchoring so the panel never detaches from the icon.
        let originX = min(
            max(buttonFrame.minX, screenFrame.minX + 8),
            screenFrame.maxX - contentSize.width - 8
        )
        let originY = buttonFrame.minY - contentSize.height - 4

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func updateStatusImage() {
        guard let button = statusItem?.button else { return }

        let connected = store.devices.contains { $0.connected.value }
        let symbol = connected ? Self.symbolConnected : Self.symbolDisconnected

        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "SteelSeries devices"
        )
        image?.isTemplate = true
        button.image = image
    }
}

// MARK: - Panel

private final class StatusBarPanel: NSPanel {

    var onEscape: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        animationBehavior = .none
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovableByWindowBackground = false
        isOpaque = false
        level = .statusBar
        titleVisibility = .hidden
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// Rounded translucent backdrop. Uses the Liquid Glass view on macOS 26 and falls
/// back to `NSVisualEffectView` on earlier systems — same behaviour, same radii.
private final class StatusBarBackgroundView: NSView {

    let contentView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        contentView.translatesAutoresizingMaskIntoConstraints = false

        let effectView: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 14
            glass.contentView = contentView
            effectView = glass
        } else {
            let visual = NSVisualEffectView()
            visual.blendingMode = .behindWindow
            visual.material = .underWindowBackground
            visual.state = .active
            visual.wantsLayer = true
            visual.layer?.cornerCurve = .continuous
            visual.layer?.cornerRadius = 14
            visual.layer?.masksToBounds = true
            visual.addSubview(contentView)
            effectView = visual
        }

        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 14
        layer?.masksToBounds = true

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: effectView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
