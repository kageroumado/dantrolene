import Foundation
import IOKit.pwr_mgt
import os

/// Public-API power-management queries used by `DisplaySleepStateMachine` and its per-edition
/// effects (the brightness-based one and the App Store overlay variant).
enum DisplayPowerInfo {
    private static let log = Logger(
        subsystem: "glass.kagerou.dantrolene", category: "DisplayPowerInfo",
    )

    /// The system's "turn display off when inactive" setting, distinguishing an explicit **Never**
    /// (0 minutes) from an unreadable value — conflating them made "Match System" silently fall back
    /// to a default timeout and black the screen against a user who chose Never.
    enum SystemDisplaySleep {
        case never
        case minutes(UInt)
        case unknown
    }

    static func systemDisplaySleep() -> SystemDisplaySleep {
        let fb = IOPMFindPowerManagement(kIOMainPortDefault)
        guard fb != 0 else {
            log.warning("Failed to open power management connection")
            return .unknown
        }
        defer { IOServiceClose(fb) }

        var minutes: UInt = 0
        let result = IOPMGetAggressiveness(fb, UInt(kPMMinutesToDim), &minutes)
        guard result == kIOReturnSuccess else { return .unknown }
        return minutes == 0 ? .never : .minutes(minutes)
    }

    /// Whether another process (video playback, a presentation app, caffeinate)
    /// currently holds a display-sleep assertion, meaning the user would not
    /// expect the display to dim.
    ///
    /// Matching on `AssertType` alone is deliberate and sufficient — no level or timed-out
    /// filtering is needed. Verified on macOS 26 against real assertions: an entry disappears from
    /// `IOPMCopyAssertionsByProcess` as soon as it stops applying, both when the owning process
    /// dies *and* when the assertion times out with the `TurnOff` action while its process stays
    /// alive. An active entry reports `AssertLevel = 255` (`kIOPMAssertionLevelOn`) and no
    /// `AssertTimedOutDate`; stale level-0 / timed-out entries are never reported, so they cannot
    /// suppress dimming here. (Recorded so the "phantom assertion" theory isn't re-litigated.)
    static func otherProcessHoldsDisplayAssertion() -> Bool {
        var rawDict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&rawDict) == kIOReturnSuccess,
              let cfDict = rawDict?.takeRetainedValue()
        else { return false }

        let dict = cfDict as NSDictionary
        let myPID = ProcessInfo.processInfo.processIdentifier

        for (key, value) in dict {
            guard let pid = (key as? NSNumber)?.int32Value,
                  pid != myPID,
                  let assertions = value as? [[String: Any]]
            else { continue }

            for assertion in assertions {
                if let type = assertion["AssertType"] as? String,
                   type == "PreventUserIdleDisplaySleep" {
                    let name = assertion["AssertName"] as? String ?? "unknown"
                    log.info("PID \(pid) holds display assertion: \(name)")
                    return true
                }
            }
        }
        return false
    }
}
