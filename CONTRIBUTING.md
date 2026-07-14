# Contributing

Bug reports and fixes are welcome. Dantrolene holds system power assertions and drives the real
backlight through private frameworks, so the most valuable contributions are grounded in what actually
happens on real hardware — a real Mac, a real home network, real sleep/wake — not what should happen
in theory.

## Bugs

Open an issue with the Bug report template. Dantrolene logs through the unified logging system; the
single most useful thing you can attach is its log:

```sh
log show --predicate 'subsystem == "glass.kagerou.dantrolene"' --last 30m --info --style compact
```

Tell us which **edition** you're on (GitHub or App Store — the Settings page footer shows it), since
display-sleep and lid-close behavior differ between them.

Security-sensitive issues shouldn't go in public issues — see [SECURITY.md](SECURITY.md).

## Build

Open in Xcode and Run the **Dantrolene** scheme:

```sh
open Dantrolene.xcodeproj
```

Two schemes: **Dantrolene** (the full GitHub edition) and **Dantrolene-AppStore** (sandboxed; the
`APPSTORE` compilation condition swaps the private-framework backlight control for overlay windows and
compiles out the Adrafinil integration). Set your development team and Run.

Or a headless compile check without local signing identities:

```sh
xcodebuild -project Dantrolene.xcodeproj -scheme Dantrolene -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
```

## Style

SwiftFormat (`.swiftformat`) and SwiftLint (`.swiftlint.yml`). Run both before committing:

```sh
swiftformat .
swiftlint
```

## Layout

- `Dantrolene/` — the SwiftUI menu-bar app (`MenuBarExtra`, window style). There is no settings
  window; deeper pages live *inside* the popover.
- `DantroleneManager` — the brain. Collapses mode, WiFi state, and location authorization into the
  single `isPreventingLock` decision, and owns the assertion / simulator / Adrafinil lifecycle. Route
  new behavior through `evaluate()` rather than special-casing it in the view.
- `ScreenLockPreventer` — holds the IOKit `PreventUserIdleDisplaySleep` assertion.
- `DisplaySleepSimulator` / `OverlayDisplaySleepSimulator` — the "dims but never locks" illusion. The
  GitHub edition drives the real backlight via private `DisplayServices`; the App Store edition
  (`APPSTORE`) uses black overlay windows.
- `WiFiMonitor` — CoreWLAN SSID reads, gated on CoreLocation authorization.
- `AdrafinilBridge` — spawns the `adrafinil` CLI to block lid-close sleep on the home network
  (`APPSTORE` builds compile this out to an inert stub). Reference-counted, TTL-bounded holds; read the
  type's doc comment before touching acquire / renew / teardown.

## Pull requests

Use the template. Reference the issue you fix and keep it focused. Because Dantrolene manipulates
system power state, behavior is hard to unit-test — **exercise it on real hardware, not just a
build**: join and leave the home network, sleep/wake, lid close/open (GitHub edition), and confirm the
assertion is actually released when it should be:

```sh
pmset -g assertions | grep -i dantrolene   # display-sleep assertion
pmset -g | grep -i SleepDisabled           # lid-close hold (GitHub edition)
```

`swiftformat --lint .` must pass. Fill in the Authorship section: agent, model, and whether the
session was attended or automatic.

Contributions are MIT-licensed.
