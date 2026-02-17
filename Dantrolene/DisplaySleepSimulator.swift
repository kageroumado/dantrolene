import Foundation
import IOKit.pwr_mgt
import os

enum DisplaySleepMode: Hashable {
    case matchSystem
    case custom(minutes: Int)

    var tag: Int {
        switch self {
        case .matchSystem: 0
        case let .custom(m): m
        }
    }

    init(tag: Int) {
        self = tag == 0 ? .matchSystem : .custom(minutes: tag)
    }
}

/// Simulates the normal display sleep sequence (dim → off → restore on activity)
/// while an IOPMAssertion prevents actual system display sleep.
///
/// Uses `DisplayServices.framework` for display brightness,
/// `KeyboardBrightnessClient` for keyboard backlight, and
/// `CGEventSourceSecondsSinceLastEventType` for idle detection.
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

    // MARK: - Display Info

    private struct Display {
        let id: UInt32
        var savedBrightness: Float
    }

    // MARK: - Keyboard Info

    private struct Keyboard {
        let id: UInt64
        var savedBrightness: Float
    }

    // MARK: - Display Framework Function Pointers

    private typealias DSGetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetBrightness = @convention(c) (UInt32, Float) -> Int32
    private typealias DSCanChange = @convention(c) (UInt32) -> Int32
    private typealias CGGetOnline = @convention(c) (
        UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?
    ) -> Int32
    private typealias IdleTimeFn = @convention(c) (Int32, UInt32) -> CFTimeInterval

    private var _getBrightness: DSGetBrightness?
    private var _setBrightness: DSSetBrightness?
    private var _canChange: DSCanChange?
    private var _getOnline: CGGetOnline?
    private var _getIdleTime: IdleTimeFn?

    // MARK: - Keyboard Framework Function Pointers

    private typealias KBGetBrFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KBSetBrFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Void
    private typealias KBIsBuiltInFn = @convention(c) (AnyObject, Selector, UInt64) -> Bool

    private var kbClient: NSObject?
    private var _kbGetBr: KBGetBrFn?
    private var _kbSetBr: KBSetBrFn?

    // MARK: - State

    private var displays: [Display] = []
    private var keyboards: [Keyboard] = []
    private var pollTask: Task<Void, Never>?
    private var dimTimeout: TimeInterval = 570
    private var offTimeout: TimeInterval = 600

    private static let dimBrightness: Float = 0.03

    // MARK: - Init

    init() {
        loadFrameworks()
    }

    // MARK: - Public

    func start(mode: DisplaySleepMode) {
        guard state == .idle else { return }
        guard _getBrightness != nil, _setBrightness != nil else {
            Self.log.error("DisplayServices not available")
            return
        }

        applyMode(mode)
        refreshDisplays()
        setupKeyboardBacklight()
        state = .active
        startPolling()

        Self.log.notice(
            "Started (dim at \(self.dimTimeout, format: .fixed(precision: 0))s, off at \(self.offTimeout, format: .fixed(precision: 0))s, \(self.displays.count) display(s), \(self.keyboards.count) keyboard(s))"
        )
    }

    func stop() {
        guard state != .idle else { return }
        pollTask?.cancel()
        pollTask = nil

        if state == .dimmed || state == .off {
            restoreAllBrightness()
            restoreKeyboardBrightness()
        }

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
            guard let minutes = readSystemDisplaySleepMinutes() else { return }
            setTimeouts(totalSeconds: TimeInterval(minutes * 60))
        case let .custom(minutes):
            setTimeouts(totalSeconds: TimeInterval(minutes * 60))
        }
    }

    private func setTimeouts(totalSeconds: TimeInterval) {
        offTimeout = totalSeconds
        dimTimeout = max(totalSeconds - 30, totalSeconds * 0.75)
    }

    // MARK: - Framework Loading

    private func loadFrameworks() {
        guard
            let ds = dlopen(
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                RTLD_LAZY
            ),
            let cg = dlopen(
                "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                RTLD_LAZY
            )
        else {
            Self.log.error("Failed to load frameworks")
            return
        }

        _ = dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            RTLD_LAZY
        )

        if let sym = dlsym(ds, "DisplayServicesGetBrightness") {
            _getBrightness = unsafeBitCast(sym, to: DSGetBrightness.self)
        }
        if let sym = dlsym(ds, "DisplayServicesSetBrightness") {
            _setBrightness = unsafeBitCast(sym, to: DSSetBrightness.self)
        }
        if let sym = dlsym(ds, "DisplayServicesCanChangeBrightness") {
            _canChange = unsafeBitCast(sym, to: DSCanChange.self)
        }
        if let sym = dlsym(cg, "CGGetOnlineDisplayList") {
            _getOnline = unsafeBitCast(sym, to: CGGetOnline.self)
        }
        if let sym = dlsym(cg, "CGEventSourceSecondsSinceLastEventType") {
            _getIdleTime = unsafeBitCast(sym, to: IdleTimeFn.self)
        }
    }

    // MARK: - System Timeout

    private func readSystemDisplaySleepMinutes() -> UInt? {
        let fb = IOPMFindPowerManagement(kIOMainPortDefault)
        guard fb != 0 else {
            Self.log.warning("Failed to open power management connection")
            return nil
        }
        defer { IOServiceClose(fb) }

        var minutes: UInt = 0
        let result = IOPMGetAggressiveness(fb, UInt(kPMMinutesToDim), &minutes)
        guard result == kIOReturnSuccess, minutes > 0 else { return nil }
        return minutes
    }

    // MARK: - Display Assertion Check

    private func otherProcessHoldsDisplayAssertion() -> Bool {
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
                    Self.log.info("PID \(pid) holds display assertion: \(name)")
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Display Management

    private func refreshDisplays() {
        guard let getOnline = _getOnline, let getBr = _getBrightness else { return }

        var count: UInt32 = 0
        _ = getOnline(0, nil, &count)
        guard count > 0 else {
            displays = []
            return
        }

        var ids = [UInt32](repeating: 0, count: Int(count))
        _ = getOnline(count, &ids, &count)

        displays = ids.compactMap { id in
            if let canChange = _canChange, canChange(id) == 0 {
                return nil
            }
            var brightness: Float = 0
            guard getBr(id, &brightness) == 0 else { return nil }
            return Display(id: id, savedBrightness: brightness)
        }
    }

    private func resaveBrightness() {
        guard let getBr = _getBrightness else { return }
        displays = displays.map { d in
            var brightness: Float = 0
            _ = getBr(d.id, &brightness)
            return Display(id: d.id, savedBrightness: brightness)
        }
        resaveKeyboardBrightness()
    }

    private func setAllDisplayBrightness(_ brightness: Float) {
        guard let setBr = _setBrightness else { return }
        for d in displays {
            _ = setBr(d.id, brightness)
        }
    }

    private func restoreAllBrightness() {
        guard let setBr = _setBrightness else { return }
        for d in displays {
            _ = setBr(d.id, d.savedBrightness)
        }
    }

    // MARK: - Keyboard Backlight

    private func setupKeyboardBacklight() {
        guard let kbcClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            return
        }

        let client = kbcClass.init()
        kbClient = client

        let copyIDsSel = Selector(("copyKeyboardBacklightIDs"))
        guard client.responds(to: copyIDsSel),
              let idsObj = client.perform(copyIDsSel)?.takeUnretainedValue() as? [Any]
        else {
            return
        }

        let getBrSel = Selector(("brightnessForKeyboard:"))
        let setBrSel = Selector(("setBrightness:forKeyboard:"))
        let isBuiltInSel = Selector(("isKeyboardBuiltIn:"))

        _kbGetBr = unsafeBitCast(
            class_getMethodImplementation(type(of: client), getBrSel)!,
            to: KBGetBrFn.self
        )
        _kbSetBr = unsafeBitCast(
            class_getMethodImplementation(type(of: client), setBrSel)!,
            to: KBSetBrFn.self
        )

        let isBuiltInFn = unsafeBitCast(
            class_getMethodImplementation(type(of: client), isBuiltInSel)!,
            to: KBIsBuiltInFn.self
        )

        for rawId in idsObj {
            guard let n = rawId as? NSNumber else { continue }
            let kbId = n.uint64Value
            guard isBuiltInFn(client, isBuiltInSel, kbId) else { continue }
            let brightness = _kbGetBr!(client, getBrSel, kbId)
            keyboards.append(Keyboard(id: kbId, savedBrightness: brightness))
        }
    }

    private func setKeyboardBrightness(_ brightness: Float) {
        guard let client = kbClient, let setBr = _kbSetBr else { return }
        let sel = Selector(("setBrightness:forKeyboard:"))
        for kb in keyboards {
            setBr(client, sel, brightness, kb.id)
        }
    }

    private func resaveKeyboardBrightness() {
        guard let client = kbClient, let getBr = _kbGetBr else { return }
        let sel = Selector(("brightnessForKeyboard:"))
        keyboards = keyboards.map { kb in
            Keyboard(id: kb.id, savedBrightness: getBr(client, sel, kb.id))
        }
    }

    private func restoreKeyboardBrightness() {
        guard let client = kbClient, let setBr = _kbSetBr else { return }
        let sel = Selector(("setBrightness:forKeyboard:"))
        for kb in keyboards {
            setBr(client, sel, kb.savedBrightness, kb.id)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                poll()
                try? await Task.sleep(for: .milliseconds(500), tolerance: .milliseconds(200))
            }
        }
    }

    private func userIdleTime() -> TimeInterval {
        guard let fn = _getIdleTime else { return 0 }
        return fn(1, 0xFFFF_FFFF)
    }

    private func restoreAndActivate() {
        restoreAllBrightness()
        restoreKeyboardBrightness()
        state = .active
    }

    private func poll() {
        let idle = userIdleTime()

        switch state {
        case .active:
            if idle >= offTimeout {
                if otherProcessHoldsDisplayAssertion() { return }
                Self.log.info("Idle \(idle, format: .fixed(precision: 0))s → OFF")
                resaveBrightness()
                setAllDisplayBrightness(0)
                setKeyboardBrightness(0)
                state = .off
            } else if idle >= dimTimeout {
                if otherProcessHoldsDisplayAssertion() { return }
                Self.log.info("Idle \(idle, format: .fixed(precision: 0))s → DIM")
                resaveBrightness()
                setAllDisplayBrightness(Self.dimBrightness)
                setKeyboardBrightness(0)
                state = .dimmed
            }

        case .dimmed:
            if idle < 1.0 {
                Self.log.info("Activity → RESTORE")
                restoreAndActivate()
            } else if idle >= offTimeout {
                if otherProcessHoldsDisplayAssertion() {
                    Self.log.info("External assertion detected → RESTORE from dim")
                    restoreAndActivate()
                    return
                }
                Self.log.info("→ OFF")
                setAllDisplayBrightness(0)
                state = .off
            }

        case .off:
            if idle < 1.0 {
                Self.log.info("Activity → RESTORE")
                restoreAndActivate()
            }

        case .idle:
            break
        }
    }
}
