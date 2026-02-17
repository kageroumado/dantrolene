import SwiftUI

@main
struct DantroleneApp: App {
    @State private var manager = DantroleneManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(manager: manager)
        } label: {
            Image(systemName: manager.isPreventingLock ? "pill.fill" : "pill")
        }
        .menuBarExtraStyle(.window)
    }
}
