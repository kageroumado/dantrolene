import Foundation
import IOKit.pwr_mgt
import os

/// Prevents screen lock by holding an IOPMAssertion that prevents idle display sleep.
///
/// When the display never sleeps due to idle, the system's lock chain never fires.
/// The assertion is automatically released by the kernel if the process crashes,
/// so no crash recovery mechanism is needed.
final class ScreenLockPreventer {
    private nonisolated static let log = Logger(
        subsystem: "glass.kagerou.dantrolene", category: "ScreenLockPreventer"
    )

    private var assertionID: IOPMAssertionID = 0
    private var isActive = false

    /// Called on the main thread when the actual prevention state changes.
    var onStateChanged: ((_ isActive: Bool) -> Void)?

    func enable() {
        guard !isActive else { return }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Dantrolene Lock Prevention" as CFString,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isActive = true
            Self.log.notice("Lock prevention enabled (assertion \(self.assertionID))")
            onStateChanged?(true)
        } else {
            Self.log.error("Failed to create IOPMAssertion: \(result)")
        }
    }

    func disable() {
        guard isActive else { return }

        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            Self.log.notice("Lock prevention disabled (released assertion \(self.assertionID))")
        } else {
            Self.log.error("Failed to release IOPMAssertion: \(result)")
        }

        assertionID = 0
        isActive = false
        onStateChanged?(false)
    }
}
