import Foundation
import IOKit.pwr_mgt
import os

/// Public-API power-management queries shared by both display sleep simulators
/// (the brightness-based one and the App Store overlay variant).
enum DisplayPowerInfo {
    private static let log = Logger(
        subsystem: "glass.kagerou.dantrolene", category: "DisplayPowerInfo",
    )

    static func systemDisplaySleepMinutes() -> UInt? {
        let fb = IOPMFindPowerManagement(kIOMainPortDefault)
        guard fb != 0 else {
            log.warning("Failed to open power management connection")
            return nil
        }
        defer { IOServiceClose(fb) }

        var minutes: UInt = 0
        let result = IOPMGetAggressiveness(fb, UInt(kPMMinutesToDim), &minutes)
        guard result == kIOReturnSuccess, minutes > 0 else { return nil }
        return minutes
    }

    /// Whether another process (video playback, a presentation app, caffeinate)
    /// currently holds a display-sleep assertion, meaning the user would not
    /// expect the display to dim.
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
