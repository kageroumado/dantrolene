# Security Policy

Dantrolene is an unprivileged menu-bar app — no root helper, no network, no accounts. Its job is to
*not* lock the screen while you're on your home WiFi, so the surface that matters is the one where it
holds the Mac awake or unlocked when it shouldn't. Reports welcome.

## Reporting a vulnerability

Please report security issues **privately**, not as public GitHub issues:

- Use GitHub's [private vulnerability reporting](https://github.com/kageroumado/dantrolene/security/advisories/new)
  (Security → Advisories → "Report a vulnerability"), or
- Reach out to [@kageroumado](https://x.com/kageroumado).

Please include a description, the affected version and **edition** (GitHub or App Store), and
reproduction steps. We aim to acknowledge within a few days. Once a fix ships, we're happy to credit
you (or keep you anonymous — your call).

## Scope — what matters most

The attack surface is intentionally small: no network connections, no server, no privileged helper,
no data collection ([PRIVACY.md](PRIVACY.md)). The highest-value targets:

- **An assertion that outlives its condition.** Dantrolene holds an IOKit `PreventUserIdleDisplaySleep`
  assertion while you're home; the GitHub edition can also hold the Mac awake through a *closed lid*
  via [Adrafinil](https://github.com/kageroumado/adrafinil). Any path that leaves either assertion
  registered after you've left the home network — or across sleep, wake, or quit — leaves a Mac
  unlocked or awake when its owner expects it locked. That's the most serious class of bug here, not a
  mere nuisance. Dantrolene releases its assertions on system sleep, re-evaluates on wake, and releases
  on terminate; every Adrafinil hold also carries a TTL so a crashed Dantrolene can't pin the Mac awake
  for long.
- **The Adrafinil CLI invocation (GitHub edition only).** Dantrolene spawns `/usr/local/bin/adrafinil`
  to place lid-close holds. Its arguments — including your home SSID, passed as `--reason` — go through
  `Process.arguments`, an execve-style argument vector, never a shell, so there is no command injection
  there. A way to make Dantrolene execute an unexpected binary, or inject an unexpected argument, would
  be in scope.

## Not a security boundary

**An SSID is a name, not a proof.** Anyone can name their hotspot what you call home, and SSIDs are
trivially spoofable. Dantrolene's "am I home?" check is a *convenience* signal, not authentication:
treat lock-prevention-at-home as comfort, not access control. This is by design, not a bug.

## Supported versions

Only the latest release and `main` receive fixes, across both the GitHub and App Store editions.
