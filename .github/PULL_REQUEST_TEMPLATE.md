<!-- Thanks for contributing to Dantrolene! Fill in what's relevant; delete what isn't. -->

## Summary

<!-- One or two sentences: what this changes, and why. -->

## Related issue(s)

<!-- e.g. "Fixes #12" or "Relates to #12". Delete if none. -->

## Changes

<!-- Bullet the key changes. Keep it skimmable. -->

-

## How it was tested

<!-- Dantrolene manipulates system power state, so behavior is hard to unit-test — say what you actually exercised on real hardware, not just that it builds. -->

- **macOS / hardware**: <!-- e.g. macOS 26.1, M4 MacBook Air -->
- **Edition**: <!-- GitHub / App Store — behavior differs -->
- **Scenarios exercised**: <!-- e.g. join/leave home network, sleep/wake, lid close/open, another app already holding a display assertion -->
- **Assertion released when it should be?**: <!-- pmset -g assertions | grep -i dantrolene ; for lid holds pmset -g | grep SleepDisabled -->
- **Result**: <!-- what you observed; screenshots / screen recordings welcome -->

## Risk / regressions

<!-- What could this break? Anything a reviewer should double-check — e.g. an assertion leaking past sleep/wake or a network change, the App Store overlay path, or the Adrafinil hold lifecycle. -->

## Checklist

- [ ] Builds (`xcodebuild … build`)
- [ ] `swiftformat --lint .` passes
- [ ] Exercised on real hardware (not just a compile)
- [ ] Confirmed the power assertion is released when it should be
- [ ] No unrelated changes bundled in

---

## Authorship

<!-- These PRs are usually written by an agent — record who wrote it and how. -->

- **Agent**: <!-- the agent's name (e.g. Sora), or the human author -->
- **Model**: <!-- the model the agent runs on, e.g. Opus 4.8 (1M context) — leave blank if human-authored -->
- **Session**: <!-- "attended" (a human participated / reviewed live) or "automatic" (unattended agent run) -->
