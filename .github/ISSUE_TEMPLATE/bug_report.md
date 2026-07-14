---
name: Bug report
about: Report a problem with Dantrolene (locks at home, won't dim, stays awake, wrong network, crash, etc.)
title: ""
labels: ""
assignees: kageroumado
---

## Summary

<!-- One or two sentences: what happens, and when. -->

## Environment

- **Dantrolene**: <!-- e.g. 1.2 — and which edition: GitHub or App Store (the Settings footer shows it) -->
- **macOS**: <!-- e.g. 26.1 (Build 25B?) -->
- **Hardware**: <!-- e.g. M4 MacBook Air, built-in display + 1 external -->
- **Mode**: <!-- Automatic / Always On / Off -->
- **Home network**: <!-- is one set? are you currently on it? -->

## Steps to reproduce

1.
2.
3.

## Expected behavior

<!-- What you expected — e.g. "the screen should not lock while on home WiFi". -->

## Actual behavior

<!-- What actually happened. Screenshots / screen recording welcome. -->

## State (optional but helpful)

After reproducing, note any of these:

- Display-sleep assertion held? `pmset -g assertions | grep -iE 'dantrolene|PreventUserIdleDisplaySleep'`
- Lid-close blocking (GitHub edition)? `pmset -g | grep -i SleepDisabled`
- Is the app running? `pgrep -x Dantrolene`
- Current WiFi name vs. your home SSID

## Log excerpt

Attach or paste the relevant lines from the unified log:

```sh
log show --predicate 'subsystem == "glass.kagerou.dantrolene"' --last 30m --info --style compact
```

This records mode changes, network transitions, assertion acquire/release, and Adrafinil holds.
