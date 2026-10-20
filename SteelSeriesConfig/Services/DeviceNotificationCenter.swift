import AppKit
import SwiftUI

/// One borderless, non-activating panel per notification.
///
/// A window rather than an overlay because a notification must be able to appear while
/// the popover is closed and the app is in the background, on top of whatever is
/// frontmost, without stealing focus. `.nonactivatingPanel` keeps the keystroke focus
/// where it was, and `.statusBar` level places it above ordinary windows — both taken
/// from the reference app's notification window, which exists for exactly this reason.
private final class NotificationPanel: NSPanel {

    init(host: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        worksWhenModal = true
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows and dismisses the floating device notifications, and keeps them stacked.
///
/// Each notification gets its own panel so they can stack and be dismissed
/// independently, and the stack is re-laid out whenever one leaves, so a gap never
/// opens where a card used to be. Ported from the reference app's `BarNotificationCenter`
/// — the stacking and anchoring maths are theirs, trimmed to one width per style.
@MainActor
final class DeviceNotificationCenter {

    static let shared = DeviceNotificationCenter()

    private struct Entry {
        let panel: NotificationPanel
        let style: NotificationStyle
    }

    private var entries: [Entry] = []

    /// Horizontal inset from the screen edge, both styles.
    private let horizontalMargin: CGFloat = 16
    /// Distance below the top of the screen for the corner style.
    private let classicTopMargin: CGFloat = 40
    /// Distance below the status item for the menu-bar style.
    private let appleTopMargin: CGFloat = 8
    private let spacing: CGFloat = 10

    private init() {}

    /// Present one notification, dismiss it after `duration`, then close it.
    func show(_ notification: DeviceNotification, style: NotificationStyle, duration: TimeInterval = 3.0) {
        // The hosting view is the panel's `contentView`, so it is sized by the panel and
        // must keep autoresizing — turning the mask off without adding constraints leaves
        // the view's size undefined, and `fittingSize` then reports a collapsed size that
        // clips the card's artwork.
        let host = NSHostingView(rootView: NotificationStyleView(notification: notification, style: style))
        let panel = NotificationPanel(host: host)
        panel.alphaValue = 0

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        // Ask the SwiftUI content how big it wants to be before sizing the panel to it.
        let size = host.fittingSize

        let origin = positionOrigin(
            size: size,
            screen: screen,
            style: style,
            stackHeight: stackHeight(on: screen, style: style)
        )

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = .init(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        entries.append(Entry(panel: panel, style: style))

        Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let self, let panel else { return }
                self.dismiss(panel)
            }
        }
    }

    /// Tear down every notification still on screen — used when the app is quitting.
    func dismissAll() {
        entries.map(\.panel).forEach(dismiss)
    }

    private func dismiss(_ panel: NotificationPanel) {
        guard let index = entries.firstIndex(where: { $0.panel === panel }) else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = .init(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            // `NSAnimationContext`'s completion handler is not main-actor isolated, but
            // tearing a window down is. Hop back before touching the panel.
            Task { @MainActor in
                panel.orderOut(nil)
                panel.close()
            }
        }

        entries.remove(at: index)
        relayout()
    }

    /// Re-stack everything on each screen, so closing a middle card does not leave a
    /// hole. Cards are walked top to bottom, each placed below the running total.
    private func relayout() {
        let byScreen = Dictionary(grouping: entries) { entry in
            entry.panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        }

        for (screen, list) in byScreen {
            guard let screen else { continue }
            var stackHeight: CGFloat = 0
            let sorted = list.sorted { $0.panel.frame.origin.y > $1.panel.frame.origin.y }

            for entry in sorted {
                let origin = positionOrigin(
                    size: entry.panel.frame.size,
                    screen: screen,
                    style: entry.style,
                    stackHeight: stackHeight
                )
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = .init(name: .easeInEaseOut)
                    entry.panel.animator().setFrameOrigin(origin)
                }
                stackHeight += entry.panel.frame.height + spacing
            }
        }
    }

    /// Combined height of the cards already on screen in this style, so a new one lands
    /// under them rather than on top.
    private func stackHeight(on screen: NSScreen, style: NotificationStyle) -> CGFloat {
        entries
            .filter { $0.style == style && ($0.panel.screen ?? NSScreen.main) == screen }
            .reduce(0) { $0 + $1.panel.frame.height + spacing }
    }

    private func positionOrigin(
        size: CGSize,
        screen: NSScreen,
        style: NotificationStyle,
        stackHeight: CGFloat
    ) -> NSPoint {
        switch style {
        case .classic: return classicOrigin(size: size, screen: screen, stackHeight: stackHeight)
        case .apple: return appleOrigin(size: size, screen: screen, stackHeight: stackHeight)
        }
    }

    /// Top-right corner of the screen — the classic notification placement.
    private func classicOrigin(size: CGSize, screen: NSScreen, stackHeight: CGFloat) -> NSPoint {
        let frame = screen.frame
        return NSPoint(
            x: frame.maxX - size.width - horizontalMargin,
            y: frame.maxY - classicTopMargin - size.height - stackHeight
        )
    }

    /// Centred under the status item when it can be found, otherwise centred on the
    /// screen — this app's own menu bar extra does the same lookup for its popover.
    private func appleOrigin(size: CGSize, screen: NSScreen, stackHeight: CGFloat) -> NSPoint {
        let statusItemFrame = visibleStatusItemFrame(on: screen)

        let x = statusItemFrame.map { $0.midX - size.width / 2 } ?? (screen.frame.midX - size.width / 2)
        let topEdge = statusItemFrame?.minY ?? screen.visibleFrame.maxY
        let y = topEdge - appleTopMargin - size.height - stackHeight

        return NSPoint(
            x: max(screen.frame.minX + horizontalMargin, min(x, screen.frame.maxX - size.width - horizontalMargin)),
            y: y
        )
    }

    /// The menu bar status item's on-screen frame, found by looking for a small window
    /// pinned to the top of the screen. Returns `nil` when it is hidden or occluded, in
    /// which case the caller falls back to centring on the screen.
    private func visibleStatusItemFrame(on screen: NSScreen) -> NSRect? {
        let topBand = CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - 60,
            width: screen.frame.width,
            height: 60
        )

        let candidates = NSApp.windows.filter { window in
            guard window.isVisible else { return false }
            guard window.frame.intersects(topBand) else { return false }
            guard window.frame.maxY >= screen.frame.maxY - 1 else { return false }
            guard window.frame.height <= 60, window.frame.width <= 260 else { return false }
            guard !entries.contains(where: { $0.panel === window }) else { return false }
            return true
        }

        return candidates.max { $0.frame.maxX < $1.frame.maxX }?.frame
    }
}
