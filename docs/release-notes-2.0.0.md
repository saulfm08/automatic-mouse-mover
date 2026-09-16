A native Apple silicon rebuild of
[automatic-mouse-mover](https://github.com/prashantgupta24/automatic-mouse-mover),
rewritten in Swift for macOS 26+.

**This is an independent rewrite, not a patched version of the original.** None
of the original Go source remains. Credit for the idea and the original
implementation belongs to [Prashant Gupta](https://github.com/prashantgupta24).
Not affiliated with or endorsed by the original author.

## Install

Download the `.dmg` (or `.zip`), open it, and drag the app to Applications.

Signed and notarized by Apple, so it opens normally on first launch — no
security warning, no right-click workaround.

## Why this exists

The original stopped working on macOS 26+ for two independent reasons:

1. The released binary was x86_64-only and unsigned, so it relied on a Rosetta
   path that is no longer viable.
2. It no longer compiles at all — its `robotgo` dependency calls
   `CGDisplayCreateImageForRect`, which Apple removed in macOS 15.

This version drops Go entirely: ~400 lines of Swift with **no third-party
dependencies**, linking only Apple system frameworks.

## What it does

Keeps your Mac awake and your status "available" by:

- Holding a power assertion so the display does not idle-sleep
- Nudging the cursor after an idle period, alternating direction so the
  pointer oscillates in place rather than drifting

Both matter. Moving the cursor alone does **not** stop the screensaver —
macOS reads a separate idle clock that cursor warping does not reset. The
nudge is kept for apps that watch pointer movement to infer presence.

## Features

- Configurable idle interval (30s / 1min / 2min / 5min)
- Configurable nudge distance (1 / 5 / 10 / 25 px)
- Status line showing last move time and live idle seconds
- Pause / Resume, with the menu bar icon dimmed while paused
- Automatic pause on system sleep, resume on wake

## Requirements

- Apple silicon Mac (arm64; Intel is not supported)
- macOS 13 or later

## Privacy

No network connections, no third-party dependencies, no input monitoring.
It reads the system idle *duration*, which cannot observe what you type.
