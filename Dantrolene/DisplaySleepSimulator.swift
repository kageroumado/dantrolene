#if !APPSTORE

    import CoreGraphics
    import Foundation
    import os

    /// Direct-distribution effects for `DisplaySleepStateMachine`: lowers the real display backlight
    /// (`DisplayServices.framework`) and keyboard backlight (`KeyboardBrightnessClient`), restoring
    /// the captured values on wake. Idle timing and the state machine live in
    /// `DisplaySleepStateMachine`; this type only knows how to darken and restore hardware.
    final class BrightnessEffects: DisplaySleepEffects {
        private nonisolated static let log = Logger(
            subsystem: "glass.kagerou.dantrolene", category: "BrightnessEffects",
        )

        // MARK: - Display / keyboard records

        private struct Display {
            let id: UInt32
            var savedBrightness: Float
        }

        private struct Keyboard {
            let id: UInt64
            var savedBrightness: Float
        }

        // MARK: - Display framework function pointers

        private typealias DSGetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
        private typealias DSSetBrightness = @convention(c) (UInt32, Float) -> Int32
        private typealias DSCanChange = @convention(c) (UInt32) -> Int32
        private typealias CGGetOnline = @convention(c) (
            UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?,
        ) -> Int32

        private var _getBrightness: DSGetBrightness?
        private var _setBrightness: DSSetBrightness?
        private var _canChange: DSCanChange?
        private var _getOnline: CGGetOnline?

        // MARK: - Keyboard framework function pointers

        private typealias KBGetBrFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
        private typealias KBSetBrFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Void
        private typealias KBIsBuiltInFn = @convention(c) (AnyObject, Selector, UInt64) -> Bool

        private var kbClient: NSObject?
        private var _kbGetBr: KBGetBrFn?
        private var _kbSetBr: KBSetBrFn?

        // MARK: - State

        private var displays: [Display] = []
        private var keyboards: [Keyboard] = []

        /// Displays a restore couldn't reach because they were asleep/inactive (e.g. a clamshelled
        /// built-in panel). Retried on later ticks once usable again, so brightness is never left
        /// stuck at 0 — the root of the brightness-corruption cluster.
        private var pendingRestore: Set<UInt32> = []

        private static let dimBrightness: Float = 0.03

        /// Instant the effects started or a display last woke. After a wake the panel brightness
        /// ramps for a few seconds; reads taken mid-ramp report transient low values. Idle time is
        /// not reset by a wake, so the first post-wake poll could otherwise capture a ramp value
        /// into `savedBrightness` and corrupt what is later restored.
        private var lastWakeInstant = ContinuousClock.now
        private var displaysWereAsleep = false
        private static let wakeSettleInterval: Duration = .seconds(5)

        init() {
            loadFrameworks()
        }

        // MARK: - DisplaySleepEffects

        func begin() -> Bool {
            guard _getBrightness != nil, _setBrightness != nil else {
                Self.log.error("DisplayServices not available")
                return false
            }
            refreshDisplays()
            setupKeyboardBacklight()
            pendingRestore.removeAll()
            lastWakeInstant = .now
            displaysWereAsleep = false
            Self.log.notice("Ready (\(self.displays.count) display(s), \(self.keyboards.count) keyboard(s))")
            return true
        }

        func tick(shouldBeAwake: Bool) -> Bool {
            // Detect a display wake (asleep → awake) and re-arm the settle window so we never
            // sample or apply brightness during the post-wake ramp, even for wakes that don't
            // restart the machine (e.g. external display sleep/wake, opening a clamshell).
            let asleepNow = displays.contains { CGDisplayIsAsleep($0.id) != 0 }
            if displaysWereAsleep, !asleepNow {
                lastWakeInstant = .now
            }
            displaysWereAsleep = asleepNow

            if shouldBeAwake {
                retryPendingRestores()
            }

            return !(asleepNow || withinWakeSettle)
        }

        func captureBaseline() {
            resaveBrightness()
        }

        func applyDim() {
            setAllDisplayBrightness(Self.dimBrightness)
            setKeyboardBrightness(0)
        }

        func applyOff() {
            setAllDisplayBrightness(0)
            setKeyboardBrightness(0)
        }

        func restore() {
            restoreAllBrightness()
            restoreKeyboardBrightness()
        }

        func end() {
            pendingRestore.removeAll()
        }

        func displayTopologyChanged() {
            guard let getOnline = _getOnline, let getBr = _getBrightness else { return }

            var count: UInt32 = 0
            _ = getOnline(0, nil, &count)
            var ids = [UInt32](repeating: 0, count: Int(count))
            if count > 0 { _ = getOnline(count, &ids, &count) }
            let liveIDs = Set(ids.prefix(Int(count)))

            // Drop displays that went away (and any pending restore for them).
            displays.removeAll { !liveIDs.contains($0.id) }
            pendingRestore.formIntersection(liveIDs)

            // Capture a baseline for genuinely new displays only — never resave existing ones,
            // which could be mid-dim/off and would poison their saved value.
            let known = Set(displays.map(\.id))
            for id in liveIDs where !known.contains(id) {
                if let canChange = _canChange, canChange(id) == 0 { continue }
                var brightness: Float = 0
                guard getBr(id, &brightness) == 0 else { continue }
                displays.append(Display(id: id, savedBrightness: brightness))
            }
            Self.log.info("Display topology changed → \(self.displays.count) display(s)")
        }

        // MARK: - Display power state

        /// A display that is asleep (system/display sleep or a clamshell-disabled built-in panel)
        /// reports unreliable brightness and must never be read from or written to.
        private func displayUsable(_ id: UInt32) -> Bool {
            CGDisplayIsAsleep(id) == 0 && CGDisplayIsActive(id) != 0
        }

        private var withinWakeSettle: Bool {
            ContinuousClock.now - lastWakeInstant < Self.wakeSettleInterval
        }

        // MARK: - Framework loading

        private func loadFrameworks() {
            guard
                let ds = dlopen(
                    "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                    RTLD_LAZY,
                ),
                let cg = dlopen(
                    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                    RTLD_LAZY,
                )
            else {
                Self.log.error("Failed to load frameworks")
                return
            }

            _ = dlopen(
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
                RTLD_LAZY,
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
        }

        // MARK: - Display management

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
                // Never overwrite a saved value while a restore is still pending for this display —
                // its current reading is our dim/off value, not the user's.
                guard displayUsable(d.id), !pendingRestore.contains(d.id) else { return d }
                var current: Float = 0
                guard getBr(d.id, &current) == 0 else { return d }
                // A reading at/below the dim floor when a higher value was saved is almost
                // certainly ours mid-transition, not the user's — don't adopt it.
                if current <= Self.dimBrightness, d.savedBrightness > Self.dimBrightness {
                    return d
                }
                return Display(id: d.id, savedBrightness: current)
            }
            resaveKeyboardBrightness()
        }

        private func setAllDisplayBrightness(_ brightness: Float) {
            guard let setBr = _setBrightness else { return }
            for d in displays where displayUsable(d.id) {
                _ = setBr(d.id, brightness)
            }
        }

        private func restoreAllBrightness() {
            guard let setBr = _setBrightness else { return }
            for d in displays {
                if displayUsable(d.id) {
                    _ = setBr(d.id, d.savedBrightness)
                    pendingRestore.remove(d.id)
                } else {
                    // Can't write to a sleeping/clamshelled panel now — retry once it wakes,
                    // otherwise it stays stuck at our dim/off value.
                    pendingRestore.insert(d.id)
                }
            }
        }

        /// Retries restores that were deferred because a display was asleep, once it is usable and
        /// past the wake-settle window. Called from the active state only, so a display that woke
        /// while the machine intends darkness isn't forced bright.
        private func retryPendingRestores() {
            guard !pendingRestore.isEmpty, !withinWakeSettle, let setBr = _setBrightness else { return }
            for d in displays where pendingRestore.contains(d.id) && displayUsable(d.id) {
                _ = setBr(d.id, d.savedBrightness)
                pendingRestore.remove(d.id)
                Self.log.info("Deferred restore completed for display \(d.id)")
            }
        }

        // MARK: - Keyboard backlight

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
                to: KBGetBrFn.self,
            )
            _kbSetBr = unsafeBitCast(
                class_getMethodImplementation(type(of: client), setBrSel)!,
                to: KBSetBrFn.self,
            )

            let isBuiltInFn = unsafeBitCast(
                class_getMethodImplementation(type(of: client), isBuiltInSel)!,
                to: KBIsBuiltInFn.self,
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
    }

#endif
