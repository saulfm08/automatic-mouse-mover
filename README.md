# Automatic Mouse Mover — native Apple silicon rebuild

> **This is an independent rewrite, not a patched version of the original.**
>
> It is a fork of [prashantgupta24/automatic-mouse-mover](https://github.com/prashantgupta24/automatic-mouse-mover)
> in the GitHub sense, and it keeps the original's purpose, behavior and MIT
> license — but **none of the original Go source remains**. The app was rebuilt
> from scratch in Swift because the original could no longer be compiled on
> current macOS. Credit for the idea, the design and the original
> implementation belongs to [Prashant Gupta](https://github.com/prashantgupta24).
>
> This fork is **not affiliated with or endorsed by** the original author, and
> has not been submitted upstream. If you want the original, use the upstream
> repo.

A menu-bar app for macOS on Apple silicon. It nudges the cursor after a period
of inactivity, so the Mac stays awake and you stay "available" in apps that
watch for idleness.

## Why this exists

The original is a Go app. On macOS 26+ it stopped working, for two independent
reasons:

1. **The released binary is x86_64-only and unsigned**, so it depended on a
   Rosetta path that is no longer viable.
2. **It no longer compiles at all.** Its `robotgo` dependency pulls in a
   screenshot library that calls `CGDisplayCreateImageForRect`, which Apple
   *removed* in macOS 15:

   ```
   error: 'CGDisplayCreateImageForRect' is unavailable:
   obsoleted in macOS 15.0 - Please use ScreenCaptureKit instead.
   ```

   That dependency exists only because `robotgo` bundles screen capture. The
   mouse mover never used it.

Because the break was in a transitive dependency rather than in the app's own
logic, patching it would have meant maintaining a pinned fork of a CGo library
the app doesn't need. Rewriting the ~400 lines that actually do the work
removed the dependency chain entirely.

## How this differs from the original

| | Original (Go) | This rewrite (Swift) |
|---|---|---|
| Language | Go + CGo | Swift |
| Dependencies | ~50 Go modules | **none** (Apple frameworks only) |
| Architecture | x86_64 via Rosetta | arm64 native |
| Builds on macOS 26+ | ✗ | ✓ |
| Idle detection | input-event hook | `CGEventSource` idle clock |
| Cursor movement | synthetic event post | `CGWarpMouseCursorPosition` |
| Blocks screensaver | incidental / unreliable | explicit `IOPMAssertion` |
| Idle interval | fixed 60s | configurable (30s–5min) |
| Nudge distance | fixed 10px | configurable (1–25px) |
| Settings storage | JSON in Application Support | `UserDefaults` |
| Menu bar icon | bundled bitmaps, 4 choices | SF Symbol (adapts to light/dark) |
| Status readout | none | last move time + live idle seconds |

### What is preserved

The behavior you'd notice: a nudge after an idle period, **alternating
direction each time** so the pointer oscillates in place instead of drifting
across the screen, and a check that the move actually landed so missing
permissions surface as an alert rather than silence.

### Two mechanisms changed deliberately

**Idle detection.** The original hooked input events to infer activity. That
requires Accessibility permission just to *observe*, and it only counts idle
time accrued since launch. This version asks the window server directly via
`CGEventSource.secondsSinceLastEventType` — the same source the screensaver
uses. It needs no permission and is correct from the moment it starts.

**Cursor movement.** `CGWarpMouseCursorPosition` moves the cursor without
posting a synthetic input event. In practice it often works without an
Accessibility grant, and because a warp is not user input it can't be mistaken
for activity on the next poll.

That second change has a consequence worth knowing if you modify this code: a
warp does **not** reset the system idle clock. Idle time keeps climbing past
the threshold, so every later poll would re-fire. Nudges are therefore
rate-limited to one per configured interval, measured from the last nudge
rather than from the idle reading.

### Why moving the cursor is not enough on its own

Moving the cursor does not stop the screensaver. macOS decides when to start
the screensaver and sleep the display by reading the HID idle clock, and
**neither warping the cursor nor posting a synthetic mouse event resets that
clock** — both were measured, and neither works. An app that only moves the
cursor will happily nudge away while the screensaver starts on top of it.

So this version holds an explicit `IOPMAssertion`
(`PreventUserIdleDisplaySleep`) for as long as it is running. That tells macOS
directly not to idle-sleep the display, instead of trying to imitate activity.
It requires no permissions, and it is released as soon as you hit Pause — or
when the machine goes to sleep deliberately, so a closed lid still sleeps.

The cursor nudge is kept because it serves a different purpose: apps that watch
for pointer movement to decide whether you are "away" (chat presence
indicators, some time trackers) need to see the pointer actually move. The two
mechanisms cover the two different things people want from this app.

You can confirm the assertion is held:

```bash
pmset -g assertions | grep "Automatic Mouse Mover"
```

## Requirements

- Apple silicon Mac
- macOS 13 or later (developed and tested on macOS 26)
- Xcode command line tools (for `swiftc`) — only if building from source

## Download

Grab the latest `.dmg` or `.zip` from the
[Releases page](https://github.com/saulfm08/automatic-mouse-mover/releases),
open it, and drag the app to Applications.

Releases are signed and notarized by Apple, so they open normally on first
launch with no security warning.

## Build and install

```bash
./scripts/build.sh --install
```

This compiles, signs, verifies, and copies to `/Applications`. Launch
"Automatic Mouse Mover" and a cursor icon appears in the menu bar.

To build without installing:

```bash
./scripts/build.sh
```

### Keeping Accessibility permission across rebuilds

macOS ties permission grants to an app's **code signature**. An ad-hoc
signature changes on every rebuild, so macOS treats each build as a new app and
silently drops the grant — the app keeps running, but the cursor stops moving.

If you plan to rebuild, create a stable local signing identity once:

```bash
./scripts/create-signing-cert.sh
```

Follow the printed steps in Keychain Access, then rebuild. `build.sh` detects
the certificate automatically.

## Menu

- **Status line** — last move time and current idle seconds
- **Pause / Resume** — the icon dims while paused
- **Move after** — 30s, 1min, 2min, 5min
- **Move by** — 1, 5, 10, or 25 pixels
- **Open Accessibility Settings…**

## Troubleshooting

**The screensaver still starts.** Check the app is running and not paused —
the menu bar icon is dimmed while paused. Then confirm the assertion is held:

```bash
pmset -g assertions | grep "Automatic Mouse Mover"
```

If nothing is listed while the app is active, the assertion failed to take;
restart the app. Note that this prevents *idle* sleep only — it deliberately
does not override closing the lid, choosing Sleep from the Apple menu, or a
lock triggered by a policy your organization manages.

**The cursor stops moving.** Open System Settings → Privacy & Security →
Accessibility and enable the app. If it is already listed *and* enabled, remove
it with "−" and add it back — that clears a stale signature association, which
is the usual cause after a rebuild.

## Privacy

The app makes **no network connections** and has no third-party dependencies;
it links only against Apple system frameworks. It reads the system idle
*duration* (how long since any input), which cannot observe what you type.

Settings live in `UserDefaults` under `com.pg.amm`:

```bash
defaults read com.pg.amm
```

The app pauses itself while the system sleeps and resumes on wake.

## Status and scope

This was built to get a working mouse mover on a specific setup (Apple silicon,
macOS 26+). It is shared as-is, in case it's useful to someone with the same
problem. There is no roadmap and no support commitment; the original project's
"no new features" policy seemed sensible and is inherited here in spirit.

Intel Macs and universal builds are intentionally not supported — see
`scripts/build.sh`.

## License

MIT, same as the original. Copyright for the original work remains with
Prashant Gupta; see [LICENSE](LICENSE).
