# Automatic Mouse Mover — Apple silicon rebuild

A native Swift rebuild of [prashantgupta24/automatic-mouse-mover](https://github.com/prashantgupta24/automatic-mouse-mover)
for macOS 26+ on Apple silicon.

It lives in the menu bar and nudges the cursor after a period of inactivity, so
the Mac stays awake and you stay "available" in apps that watch for idleness.

## Why a rebuild

The original is a Go app. On macOS 26+ it stopped working for two reasons:

1. **The shipped binary is x86_64 only and unsigned.** It relied on Rosetta,
   which is no longer a viable path for an unsigned Intel binary.
2. **It no longer compiles.** Its `robotgo` dependency pulls in a screenshot
   library that calls `CGDisplayCreateImageForRect`, which Apple *removed* in
   macOS 15:

   ```
   error: 'CGDisplayCreateImageForRect' is unavailable:
   obsoleted in macOS 15.0 - Please use ScreenCaptureKit instead.
   ```

   That dependency exists only because `robotgo` bundles screen capture. The
   mouse mover never used it.

This version drops Go entirely: ~400 lines of Swift against AppKit and
CoreGraphics, no third-party dependencies, building arm64-native.

## Improvements over the original

| | Original | This version |
|---|---|---|
| Architecture | x86_64 (Rosetta) | arm64 native |
| Dependencies | ~50 Go modules, CGo | none |
| Idle detection | input-event hook | `CGEventSource` idle clock |
| Cursor move | synthetic event post | `CGWarpMouseCursorPosition` |
| Interval | fixed 60s | configurable |

Two of these are worth expanding on:

**Idle detection.** The original hooked input events to infer activity, which
required Accessibility permission just to *observe*, and missed idle time that
accrued before launch. This version asks the window server directly via
`CGEventSource.secondsSinceLastEventType` — the same source the screensaver
uses. No permission needed, and it is correct from the moment it starts.

**Cursor movement.** `CGWarpMouseCursorPosition` moves the cursor without
posting a synthetic input event. It does not require Accessibility permission in
the common case, and because the warp is not user input it cannot be mistaken
for activity on the next poll.

## Build and install

```bash
./scripts/build.sh --install
```

This compiles, signs, verifies, and copies to `/Applications`. Then launch
"Automatic Mouse Mover" — a cursor icon appears in the menu bar.

### Keeping Accessibility permission across rebuilds

macOS ties permission grants to an app's code signature. An ad-hoc signature
changes on every rebuild, so macOS treats each build as a new app and silently
drops the grant — the app keeps running but the cursor stops moving.

If you plan to rebuild, create a stable local signing identity once:

```bash
./scripts/create-signing-cert.sh
```

Follow the printed steps in Keychain Access, then rebuild. The build script
picks up the certificate automatically.

## Menu

- **Status line** — last move time and current idle seconds
- **Pause / Resume** — the icon dims while paused
- **Move after** — 30s, 1min, 2min, 5min
- **Move by** — 1, 5, 10, or 25 pixels
- **Open Accessibility Settings…**

Each nudge alternates direction, so the cursor oscillates around where you left
it rather than drifting across the screen.

## If the cursor stops moving

Open System Settings → Privacy & Security → Accessibility and enable the app.
If it is already listed *and* enabled, remove it with "−" and add it back —
that clears a stale signature association, which is the usual cause.

## Notes

Settings persist in `UserDefaults` (`com.pg.amm`). To inspect or change them
without the menu:

```bash
defaults read com.pg.amm
```

The app pauses itself while the system sleeps and resumes on wake.

## License

MIT, as the original. Based on the work of Prashant Gupta.
