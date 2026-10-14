# dantrolene reference

[Overview](README.md)

## How it works

macOS locks the screen when the display sleeps due to idle timeout. Dantrolene prevents this by
holding an IOKit power assertion (`PreventUserIdleDisplaySleep`) that tells the system not to
idle-sleep the display. Since the display never idle-sleeps, the lock chain never fires.

To avoid the display staying lit forever, Dantrolene includes a **display sleep simulator** that
mimics the native behavior: after a configurable idle timeout (or matching your system setting),
it dims the display to near-zero, then turns it off entirely. Any user activity instantly restores
the original brightness. The GitHub edition drives the real backlight through Apple's private
`DisplayServices.framework` (and `KeyboardBrightnessClient` for the keyboard); the App Store
edition simulates the same sequence with black overlay windows, since sandboxed apps can't touch
private frameworks.

WiFi SSID detection uses CoreWLAN with CoreLocation authorization (macOS requires Location
Services permission to read the current SSID). The network name is compared on-device and never
leaves your Mac.

> **服用注意 ・ side effects.** An SSID is a name, not a proof: anyone can call their hotspot what
> you call home, so treat this as comfort, not security. The GitHub edition's backlight dimming
> rides on private frameworks, so a macOS update may break it someday.

## Building

```sh
git clone https://github.com/kageroumado/dantrolene.git
cd dantrolene
open Dantrolene.xcodeproj
```

Two schemes: **Dantrolene** (the GitHub edition) and **Dantrolene-AppStore** (sandboxed; the
`APPSTORE` compilation condition swaps the private-framework display sleep for overlay windows
and compiles out the Adrafinil integration). Select one, set your development team, Run.

For a headless compile check without local signing identities:

```sh
xcodebuild -project Dantrolene.xcodeproj -scheme Dantrolene -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
```
