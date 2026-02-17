# Dantrolene

A macOS menu bar utility that automatically prevents screen lock when connected to your home WiFi network.

Named after [dantrolene](https://en.wikipedia.org/wiki/Dantrolene), the muscle relaxant that prevents muscles from locking up — this app prevents your screen from locking up.

## Features

- **Three modes**: Automatic (WiFi-based), Always On, Off
- **Display sleep simulation**: Dims and turns off the display after idle timeout, restoring on activity — behaves like native display sleep while the lock assertion is active
- **Conflict-aware**: Detects when other apps (Zoom, presentations) hold display assertions and backs off
- **Launch at Login** via ServiceManagement
- **Sleep/wake aware**: Releases assertions on system sleep, re-evaluates on wake

## How it works

macOS locks the screen when the display sleeps due to idle timeout. Dantrolene prevents this by holding an IOKit power assertion (`PreventUserIdleDisplaySleep`) that tells the system not to idle-sleep the display. Since the display never idle-sleeps, the lock chain never fires.

To avoid the display staying on forever, Dantrolene includes a **display sleep simulator** that mimics the native behavior: after a configurable idle timeout (or matching your system setting), it dims the display brightness to near-zero, then turns it off entirely. Any user activity instantly restores the original brightness. This uses Apple's private `DisplayServices.framework` for display brightness and `KeyboardBrightnessClient` for keyboard backlight control.

WiFi SSID detection uses CoreWLAN with CoreLocation authorization (macOS requires Location Services permission to read the current SSID).

## Requirements

- macOS 26+
- Location Services permission (required by macOS to read WiFi SSID)

## Setup

1. Launch the app — a pill icon appears in the menu bar
2. Grant Location Services when prompted
3. Click the pill icon → **Use Current** to set your home network
4. Enable **Launch at Login** to start automatically
