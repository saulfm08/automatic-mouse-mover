import AppKit
import CoreGraphics
import os

/// Drives the cursor when the machine has been idle.
///
/// Design note: the original Go app ran an activity tracker that hooked input
/// events to decide whether the user had been active. That needs Accessibility
/// permission just to *observe*, and it misses idle time accrued before launch.
/// `CGEventSource.secondsSinceLastEventType` asks the window server directly,
/// needs no permission at all, and is what the screensaver itself uses.
/// Accessibility is then only required to *move* the cursor.
final class MouseMover {
    /// How often we check the idle clock. Independent of the idle threshold:
    /// polling is cheap, and a short tick keeps the nudge punctual.
    private static let pollInterval: TimeInterval = 5

    /// A move smaller than this is treated as "didn't actually move",
    /// absorbing any sub-point rounding by the window server.
    private static let movementEpsilon: CGFloat = 0.5

    private let log = Logger(subsystem: "com.pg.amm", category: "MouseMover")

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.pg.amm.mover")

    /// Flips each nudge so the cursor oscillates around its resting place
    /// instead of marching across the screen.
    private var direction = 1

    private var settings: Settings
    /// Set while the system is asleep, so we don't fight the display.
    private var isSystemAsleep = false

    /// Raised when a nudge is attempted but the cursor does not move —
    /// almost always missing Accessibility permission.
    var onPermissionProblem: (() -> Void)?
    /// Fires after each successful nudge, so the UI can show the time.
    var onNudge: ((Date) -> Void)?

    /// Guarded by `stateLock` because the timer queue writes it and the
    /// main thread reads it to render the menu.
    private let stateLock = NSLock()
    private var _lastNudge: Date?
    var lastNudge: Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastNudge
    }

    private var hasReportedPermissionProblem = false

    init(settings: Settings) {
        self.settings = settings
        registerForSleepNotifications()
    }

    // MARK: - Lifecycle

    func start() {
        queue.sync {
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.pollInterval,
                           repeating: Self.pollInterval)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
        log.info("mouse mover started")
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
        // Clear the rate-limit anchor so resuming does not inherit a stale
        // "already nudged recently" from before the pause.
        stateLock.lock()
        _lastNudge = nil
        stateLock.unlock()
        log.info("mouse mover stopped")
    }

    var isRunning: Bool {
        queue.sync { timer != nil }
    }

    func update(settings: Settings) {
        queue.sync { self.settings = settings }
    }

    // MARK: - Core loop

    private func tick() {
        guard !isSystemAsleep else {
            log.debug("system asleep, skipping tick")
            return
        }

        guard Self.systemIdleTime() >= settings.idleInterval else { return }

        // Warping the cursor does not reset the HID idle clock, so idle time
        // keeps climbing and every later poll would re-fire. Rate-limit to one
        // nudge per interval, measured from the last nudge we actually made.
        if let last = lastNudge, Date().timeIntervalSince(last) < settings.idleInterval {
            return
        }

        nudge()
    }

    /// Seconds since the last user input of any kind.
    ///
    /// `.anyInputEventType` covers mouse, keyboard, scroll and tablet events,
    /// so moving *or* typing both count as activity.
    static func systemIdleTime() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .init(rawValue: ~0)!  // kCGAnyInputEventType
        )
    }

    /// Move the cursor, then read it back to confirm the move landed.
    private func nudge() {
        guard let before = CGEvent(source: nil)?.location else {
            log.error("could not read cursor position")
            return
        }

        let delta = CGFloat(settings.nudgeDistance * direction)
        let target = clampToScreen(CGPoint(x: before.x + delta, y: before.y + delta))

        // Warp rather than posting a mouse-moved event: warping does not count
        // as user input, so it cannot mask genuine activity on the next tick.
        CGWarpMouseCursorPosition(target)
        // Reunite the hardware cursor with the warped position; without this
        // the next physical mouse move can snap back to the old location.
        CGAssociateMouseAndMouseCursorPosition(1)

        guard let after = CGEvent(source: nil)?.location else { return }
        let moved = abs(after.x - before.x) > Self.movementEpsilon
            || abs(after.y - before.y) > Self.movementEpsilon

        if moved {
            direction *= -1
            stateLock.lock()
            _lastNudge = Date()
            stateLock.unlock()
            hasReportedPermissionProblem = false
            log.info("nudged cursor to \(target.debugDescription, privacy: .public)")
            let now = Date()
            DispatchQueue.main.async { [weak self] in self?.onNudge?(now) }
        } else {
            log.error("cursor did not move — Accessibility permission is likely missing")
            reportPermissionProblemOnce()
        }
    }

    /// Keep the target inside a real display, so a nudge near the edge
    /// is not silently clamped by the window server and read back as "no move".
    private func clampToScreen(_ point: CGPoint) -> CGPoint {
        // NSScreen is main-thread-affine in principle, but frame reads are safe
        // and this avoids a hop on every nudge.
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return point }

        // CoreGraphics is top-left origin; NSScreen is bottom-left. Convert.
        let totalHeight = screens.map { $0.frame.maxY }.max() ?? 0
        let cgFrames = screens.map { screen -> CGRect in
            CGRect(x: screen.frame.minX,
                   y: totalHeight - screen.frame.maxY,
                   width: screen.frame.width,
                   height: screen.frame.height)
        }

        if cgFrames.contains(where: { $0.insetBy(dx: 2, dy: 2).contains(point) }) {
            return point
        }

        // Outside every display: reflect the nudge back inward instead.
        return CGPoint(x: point.x - CGFloat(settings.nudgeDistance * direction * 2),
                       y: point.y - CGFloat(settings.nudgeDistance * direction * 2))
    }

    private func reportPermissionProblemOnce() {
        guard !hasReportedPermissionProblem else { return }
        hasReportedPermissionProblem = true
        DispatchQueue.main.async { [weak self] in self?.onPermissionProblem?() }
    }

    // MARK: - Sleep handling

    private func registerForSleepNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.queue.async { self?.isSystemAsleep = true }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.queue.async { self?.isSystemAsleep = false }
        }
    }
}
