import Foundation
import IOKit.pwr_mgt
import os

/// Holds a power-management assertion that keeps the display awake.
///
/// Why this exists alongside the cursor nudge: moving the cursor does **not**
/// reset the system's HID idle clock, and the screensaver reads that clock.
/// So a nudge alone keeps a *watching app* seeing movement, but does not stop
/// macOS from starting the screensaver or sleeping the display.
///
/// `IOPMAssertion` addresses that directly — it tells macOS not to idle-sleep,
/// rather than trying to simulate activity. It needs no permissions.
final class IdleAssertion {
    private let log = Logger(subsystem: "com.pg.amm", category: "IdleAssertion")
    private let lock = NSLock()
    private var assertionID: IOPMAssertionID = 0
    private var isHeld = false

    /// `PreventUserIdleDisplaySleep` also implies the system stays awake, and
    /// it is what "keep the screen on" tools use. It does not stop sleep when
    /// the lid is closed or the user explicitly sleeps the machine.
    private static let assertionType = kIOPMAssertionTypePreventUserIdleDisplaySleep

    func acquire() {
        lock.lock()
        defer { lock.unlock() }
        guard !isHeld else { return }

        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            Self.assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Automatic Mouse Mover is keeping this Mac awake" as CFString,
            &id
        )

        guard result == kIOReturnSuccess else {
            log.error("could not create power assertion (error \(result))")
            return
        }
        assertionID = id
        isHeld = true
        log.info("holding display-sleep assertion")
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        guard isHeld else { return }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isHeld = false
        log.info("released display-sleep assertion")
    }

    deinit {
        // Not going through release() — deinit cannot safely take the lock if
        // a caller is mid-release, and the process is going away regardless.
        if isHeld {
            IOPMAssertionRelease(assertionID)
        }
    }
}
