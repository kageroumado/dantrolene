#if DEBUG

    import AppKit
    import Propofol
    import SwiftUI

    /// A chrome-less stage for capturing clean popover screenshots.
    ///
    /// The real MenuBarExtra popover is useless for marketing captures: its vibrancy material
    /// samples whatever happens to be behind the window (muddy grays), and the window object
    /// lingers off-screen after dismissal — `screencapture -l` happily grabs stale content.
    ///
    /// The stage shows the same `MenuBarPopoverView`, bound to the same live manager (so it is
    /// fully interactive), in Propofol's `PopoverStageWindow` — one window forced light, one
    /// forced dark. Capture with `screencapture -l <window id> -o out.png`.
    ///
    /// Present by launching with `-DANTROLENE_GALLERY 1`; pair with `DANTROLENE_FAKE_SSID` in
    /// the environment (see `WiFiMonitor`) to stage home/away states on any machine. Tinted
    /// glass takes its color only in the key window, so launch once per shot with
    /// `-DANTROLENE_GALLERY_KEY light` or `dark` and capture that window.
    @MainActor
    enum ScreenshotGallery {
        private static var windows: [NSWindow] = []

        static func present(manager: DantroleneManager) {
            guard windows.isEmpty else {
                windows.forEach { $0.makeKeyAndOrderFront(nil) }
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let light = PopoverStageWindow(title: "Dantrolene — Stage (Light)") {
                MenuBarPopoverView(manager: manager)
            }
            let dark = PopoverStageWindow(title: "Dantrolene — Stage (Dark)", dark: true) {
                MenuBarPopoverView(manager: manager)
            }
            light.center()
            let origin = light.frame.origin
            light.setFrameOrigin(NSPoint(x: origin.x - light.frame.width * 0.7, y: origin.y))
            dark.setFrameOrigin(NSPoint(x: origin.x + dark.frame.width * 0.7, y: origin.y))

            windows = [light, dark]
            windows.forEach { $0.orderFront(nil) }
            presentSymbolLab()
            let darkIsKey = UserDefaults.standard.string(forKey: "DANTROLENE_GALLERY_KEY") == "dark"
            (darkIsKey ? dark : light).makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        // MARK: - Symbol lab

        private static var labWindow: NSWindow?

        /// A plain window with a free-floating toggle (wired to nothing) driving the
        /// house⇄padlock symbol transition, for judging the state-change animation by hand.
        /// The menu bar item itself never animates — MenuBarExtra labels don't run symbol
        /// effects — so this is where the transition is evaluated.
        private static func presentSymbolLab() {
            if let labWindow {
                labWindow.makeKeyAndOrderFront(nil)
                return
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: SymbolLabView()))
            window.title = "Dantrolene — Symbol Lab"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX + 400, y: window.frame.maxY))
            labWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }

    private struct SymbolLabView: View {
        @State private var locked = false
        @State private var scrub: CGFloat = 0

        var body: some View {
            VStack(spacing: 24) {
                Toggle("Locked", isOn: $locked.animation(.smooth(duration: 0.45)))
                    .toggleStyle(.switch)

                labRow("MorphingMark — true path interpolation") {
                    MorphingMark(progress: locked ? 1 : 0)
                        .frame(width: 72, height: 72)
                    MorphingMark(progress: locked ? 1 : 0)
                        .frame(width: 18, height: 18)
                }

                labRow("scrub the fold by hand") {
                    VStack(spacing: 8) {
                        MorphingMark(progress: scrub, animation: nil)
                            .frame(width: 72, height: 72)
                        Slider(value: $scrub, in: 0 ... 1)
                            .frame(width: 180)
                    }
                }

                labRow("MenuBarIcon — constant canvas, both states") {
                    menuBarStrip(dark: false)
                    menuBarStrip(dark: true)
                }

                labRow("locked detail candidates — plain · dot · keyhole") {
                    lockedDetailStrip(dark: false)
                    lockedDetailStrip(dark: true)
                }
            }
            .padding(28)
            .frame(minWidth: 420)
        }

        /// Both menu bar images side by side on a bar-like background, template-tinted the
        /// way the real menu bar would render them.
        private func menuBarStrip(dark: Bool) -> some View {
            HStack(spacing: 10) {
                Image(nsImage: MenuBarIcon.image(locked: false))
                Image(nsImage: MenuBarIcon.image(locked: true))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(dark ? Color.black.opacity(0.85) : Color(white: 0.92), in: RoundedRectangle(cornerRadius: 6))
            .environment(\.colorScheme, dark ? .dark : .light)
        }

        /// The home mark followed by each locked-detail candidate, for judging how much
        /// interior the padlock should keep at menu bar size.
        private func lockedDetailStrip(dark: Bool) -> some View {
            HStack(spacing: 10) {
                Image(nsImage: MenuBarIcon.image(locked: false))
                ForEach(MenuBarIcon.LockedDetail.allCases, id: \.self) { detail in
                    Image(nsImage: MenuBarIcon.image(locked: true, detail: detail))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(dark ? Color.black.opacity(0.85) : Color(white: 0.92), in: RoundedRectangle(cornerRadius: 6))
            .environment(\.colorScheme, dark ? .dark : .light)
        }

        private func labRow(_ caption: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 40) {
                    content()
                }
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

#endif
