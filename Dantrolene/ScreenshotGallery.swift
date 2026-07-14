#if DEBUG

    import AppKit
    import SwiftUI

    /// A chrome-less stage for capturing clean popover screenshots.
    ///
    /// The real MenuBarExtra popover is useless for marketing captures: its vibrancy material
    /// samples whatever happens to be behind the window (muddy grays), the system window has
    /// its own corner treatment that captures poorly, and the window object lingers off-screen
    /// after dismissal — `screencapture -l` happily grabs stale content.
    ///
    /// This window shows the same `MenuBarPopoverView`, bound to the same live manager (so it
    /// is fully interactive — click Use Current, flip toggles), on an opaque window background
    /// with proper rounded alpha corners and no shadow. Capture it with the system screenshot
    /// picker (⇧⌘4, space, click) or `screencapture -l <window id>`.
    ///
    /// Present by launching with `-DANTROLENE_GALLERY 1`; pair with `DANTROLENE_FAKE_SSID` in
    /// the environment (see `WiFiMonitor`) to stage home/away states on any machine.
    @MainActor
    enum ScreenshotGallery {
        private static var window: NSWindow?

        static func present(manager: DantroleneManager) {
            if let window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let hosting = NSHostingController(rootView: StageView(manager: manager))
            let stage = KeyableBorderlessWindow(contentViewController: hosting)
            stage.styleMask = [.borderless]
            stage.title = "Dantrolene — Screenshot Stage"
            stage.isOpaque = false
            stage.backgroundColor = .clear
            stage.hasShadow = false
            stage.isMovableByWindowBackground = true
            stage.isReleasedWhenClosed = false
            stage.level = .floating
            stage.center()
            window = stage
            stage.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Borderless windows refuse key status by default, which would make the stage's
    /// controls (Use Current, the toggles) unclickable.
    private final class KeyableBorderlessWindow: NSWindow {
        override var canBecomeKey: Bool {
            true
        }
    }

    private struct StageView: View {
        @Bindable var manager: DantroleneManager

        private static let cornerRadius: CGFloat = 13

        var body: some View {
            MenuBarPopoverView(manager: manager)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .padding(1)
        }
    }

#endif
