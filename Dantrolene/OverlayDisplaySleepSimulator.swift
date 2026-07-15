#if APPSTORE

    import AppKit
    import Foundation
    import os

    /// App Store effects for `DisplaySleepStateMachine`. Sandboxed builds can't touch the private
    /// DisplayServices/CoreBrightness frameworks the direct edition drives, so instead of lowering
    /// the backlight this covers every screen with black borderless windows — translucent for dim,
    /// opaque for off. The panel stays lit underneath; visually the effect matches, which is all the
    /// lock-prevention use case needs (a dark screen that never locks).
    ///
    /// The overlays absorb mouse clicks so a blind click into a "sleeping" screen can't land on
    /// whatever sits beneath; any HID activity still advances the system idle clock, which the state
    /// machine watches to tear the overlays down.
    final class OverlayEffects: DisplaySleepEffects {
        private nonisolated static let log = Logger(
            subsystem: "glass.kagerou.dantrolene", category: "OverlayEffects",
        )

        private enum Constants {
            static let dimAlpha: CGFloat = 0.7
            static let offAlpha: CGFloat = 1.0
            static let fadeDuration: TimeInterval = 0.6
        }

        private var overlayWindows: [NSWindow] = []
        private var currentAlpha: CGFloat = 0
        /// The app that was frontmost when the off-stage overlay took key, so activation can be
        /// handed back on wake rather than leaving the user in Dantrolene.
        private var appBeforeTakingKey: NSRunningApplication?

        // MARK: - DisplaySleepEffects

        func begin() -> Bool {
            true
        }

        /// Overlays never sample hardware, so there's nothing to guard against; always ready.
        func tick(shouldBeAwake _: Bool) -> Bool {
            true
        }

        func captureBaseline() {}

        func applyDim() {
            showOverlays(alpha: Constants.dimAlpha, animated: true)
        }

        func applyOff() {
            showOverlays(alpha: Constants.offAlpha, animated: true)
            takeKeyToSwallowWakeKeystroke()
        }

        func restore() {
            removeOverlays()
            returnKeyToPreviousApp()
        }

        func end() {
            removeOverlays()
            returnKeyToPreviousApp()
        }

        func displayTopologyChanged() {
            // Rebuild the overlays for the new screen set if we're currently covering the display,
            // so a screen added or removed mid-"sleep" is handled at once.
            guard !overlayWindows.isEmpty else { return }
            let alpha = currentAlpha
            removeOverlays()
            showOverlays(alpha: alpha, animated: false)
            // The window that held key was just closed; hand it to the rebuilt one so the off stage
            // keeps swallowing keystrokes. `appBeforeTakingKey` is already recorded — don't re-capture
            // it here or we'd remember Dantrolene itself as the app to return to.
            if alpha == Constants.offAlpha, let window = overlayWindows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }

        // MARK: - Key handling

        /// The screen is black in the off stage, so the keystroke a user presses to "wake" it is
        /// aimed at nothing — but without key status it lands in whatever app sits hidden behind the
        /// overlay (Space toggles playback, Return sends a half-typed message). Take key while off so
        /// that keystroke dies here instead. The machine wakes on the idle clock, not on the event.
        private func takeKeyToSwallowWakeKeystroke() {
            guard appBeforeTakingKey == nil, let window = overlayWindows.first else { return }
            appBeforeTakingKey = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        /// Hand activation back to whoever had it, so waking doesn't strand the user in Dantrolene.
        private func returnKeyToPreviousApp() {
            guard let previous = appBeforeTakingKey else { return }
            appBeforeTakingKey = nil
            guard !previous.isTerminated, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            previous.activate()
        }

        // MARK: - Overlay windows

        private func showOverlays(alpha: CGFloat, animated: Bool) {
            if overlayWindows.isEmpty {
                overlayWindows = NSScreen.screens.map(Self.makeOverlayWindow)
            }
            currentAlpha = alpha
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
            currentAlpha = 0
        }

        private static func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
            let window = KeystrokeSwallowingWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
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
    }

    /// Borderless windows refuse key status by default, which is what let the waking keystroke fall
    /// through to the app hidden behind a black overlay. This one accepts key and eats the event:
    /// the state machine wakes off the idle clock, so nothing here needs to act on it, and
    /// `NSResponder`'s default would beep at the user.
    private final class KeystrokeSwallowingWindow: NSWindow {
        override var canBecomeKey: Bool {
            true
        }
        override func keyDown(with _: NSEvent) {}
        override func keyUp(with _: NSEvent) {}
        override func flagsChanged(with _: NSEvent) {}
    }

#endif
