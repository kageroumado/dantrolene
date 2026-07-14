import SwiftUI

@main
struct DantroleneApp: App {
    @State private var manager: DantroleneManager

    init() {
        let manager = DantroleneManager()
        _manager = State(initialValue: manager)

        #if DEBUG
            // Chrome-less popover stage for clean screenshot captures (see ScreenshotGallery).
            // A menu-bar (LSUIElement) app never auto-presents SwiftUI windows, so it is
            // presented via AppKit after launch settles.
            if UserDefaults.standard.bool(forKey: "DANTROLENE_GALLERY") {
                DispatchQueue.main.async {
                    ScreenshotGallery.present(manager: manager)
                }
            }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(manager: manager)
        } label: {
            Image(systemName: manager.isPreventingLock ? "pill.fill" : "pill")
                .accessibilityLabel("Dantrolene")
        }
        .menuBarExtraStyle(.window)
    }
}
