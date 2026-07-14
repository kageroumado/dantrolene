#if APPSTORE

import AppKit
import CoreGraphics
import Foundation
import os

/// App Store variant of the display sleep simulation (dim → off → restore on activity).
///
/// Sandboxed builds cannot touch the private DisplayServices/CoreBrightness frameworks the
/// direct-distribution simulator drives, so instead of lowering the backlight this variant
/// covers every screen with black borderless windows — translucent for the dim stage, opaque
/// for off. The panel stays lit underneath; visually the effect matches, which is what the
/// lock-prevention use case needs (the point is a dark screen that never locks).
///
/// The overlay windows absorb mouse clicks so a blind click into a "sleeping" screen can't
/// land on whatever sits beneath; any HID activity still advances the system idle clock,
/// which the poll loop watches to tear the overlays down.
final class DisplaySleepSimulator {
    private enum State {
        case idle
        case active
        case dimmed
        case off
    }

    private var state: State = .idle

    private nonisolated static let log = Logger(
        subsystem: "glass.kagerou.dantrolene", category: "DisplaySleepSimulator"
    )

    private enum Constants {
        static let dimAlpha: CGFloat = 0.7
        static let fadeDuration: TimeInterval = 0.6
        static let pollInterval: Duration = .milliseconds(500)
    }

    // MARK: - State

    private var overlayWindows: [NSWindow] = []
    private var pollTask: Task<Void, Never>?
    private var dimTimeout: TimeInterval = 570
    private var offTimeout: TimeInterval = 600

    // MARK: - Public

    func start(mode: DisplaySleepMode) {
        guard state == .idle else { return }
        applyMode(mode)
        state = .active
        startPolling()

        Self.log.notice(
            "Started overlay simulator (dim at \(self.dimTimeout, format: .fixed(precision: 0))s, off at \(self.offTimeout, format: .fixed(precision: 0))s)"
        )
    }

    func stop() {
        guard state != .idle else { return }
        pollTask?.cancel()
        pollTask = nil
        removeOverlays()
        state = .idle
        Self.log.notice("Stopped")
    }

    func updateTimeout(_ mode: DisplaySleepMode) {
        guard state != .idle else { return }
        applyMode(mode)
        Self.log.info(
            "Updated timeouts (dim at \(self.dimTimeout, format: .fixed(precision: 0))s, off at \(self.offTimeout, format: .fixed(precision: 0))s)"
        )
    }

    // MARK: - Timeout Configuration

    private func applyMode(_ mode: DisplaySleepMode) {
        switch mode {
        case .matchSystem:
            guard let minutes = DisplayPowerInfo.systemDisplaySleepMinutes() else { return }
            setTimeouts(totalSeconds: TimeInterval(minutes * 60))
        case let .custom(minutes):
            setTimeouts(totalSeconds: TimeInterval(minutes * 60))
        }
    }

    private func setTimeouts(totalSeconds: TimeInterval) {
        offTimeout = totalSeconds
        dimTimeout = max(totalSeconds - 30, totalSeconds * 0.75)
    }

    // MARK: - Overlay Windows

    private func showOverlays(alpha: CGFloat, animated: Bool) {
        // Rebuilt on every dim entry so a screen added or removed while active
        // is covered correctly the next time the displays "sleep".
        if overlayWindows.isEmpty {
            overlayWindows = NSScreen.screens.map(Self.makeOverlayWindow)
        }
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.fadeDuration
                for window in overlayWindows {
                    window.animator().alphaValue = alpha
                }
            }
        } else {
            for window in overlayWindows {
                window.alphaValue = alpha
            }
        }
    }

    /// Instant, not animated: waking should feel immediate.
    private func removeOverlays() {
        for window in overlayWindows {
            window.close()
        }
        overlayWindows = []
    }

    private static func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .black
        window.isOpaque = false
        window.alphaValue = 0
        window.level = .screenSaver
        window.hasShadow = false
        // Absorb clicks: a blind click into a dark screen must not reach the UI beneath.
        // Borderless windows refuse key status, so focus stays where it was.
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        return window
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                poll()
                try? await Task.sleep(for: Constants.pollInterval, tolerance: .milliseconds(200))
            }
        }
    }

    /// Seconds since the last hardware input event. `kCGAnyInputEventType` has no Swift
    /// spelling, so this takes the minimum across the event types a user actually wakes
    /// a machine with.
    private static let watchedEventTypes: [CGEventType] = [
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged,
        .keyDown, .flagsChanged, .scrollWheel,
    ]

    private func userIdleTime() -> TimeInterval {
        Self.watchedEventTypes
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .min() ?? 0
    }

    private func poll() {
        let idle = userIdleTime()

        switch state {
        case .active:
            if idle >= offTimeout {
                if DisplayPowerInfo.otherProcessHoldsDisplayAssertion() { return }
                Self.log.info("Idle \(idle, format: .fixed(precision: 0))s → OFF")
                showOverlays(alpha: 1.0, animated: true)
                state = .off
            } else if idle >= dimTimeout {
                if DisplayPowerInfo.otherProcessHoldsDisplayAssertion() { return }
                Self.log.info("Idle \(idle, format: .fixed(precision: 0))s → DIM")
                showOverlays(alpha: Constants.dimAlpha, animated: true)
                state = .dimmed
            }

        case .dimmed:
            if idle < 1.0 {
                Self.log.info("Activity → RESTORE")
                removeOverlays()
                state = .active
            } else if idle >= offTimeout {
                if DisplayPowerInfo.otherProcessHoldsDisplayAssertion() {
                    Self.log.info("External assertion detected → RESTORE from dim")
                    removeOverlays()
                    state = .active
                    return
                }
                Self.log.info("→ OFF")
                showOverlays(alpha: 1.0, animated: true)
                state = .off
            }

        case .off:
            if idle < 1.0 {
                Self.log.info("Activity → RESTORE")
                removeOverlays()
                state = .active
            }

        case .idle:
            break
        }
    }
}

#endif
