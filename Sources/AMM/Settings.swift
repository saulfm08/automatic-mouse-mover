import Foundation

/// User-configurable options, persisted in UserDefaults.
///
/// The original Go app stored these as JSON in ~/Library/Application Support/amm.
/// UserDefaults is the platform-native equivalent and survives app replacement.
struct Settings {
    /// Seconds of no user input before the cursor is nudged.
    var idleInterval: TimeInterval
    /// How far, in points, each nudge moves the cursor.
    var nudgeDistance: Int
    /// Whether the mover is currently armed.
    var isEnabled: Bool

    static let availableIntervals: [TimeInterval] = [30, 60, 120, 300]
    static let availableDistances: [Int] = [1, 5, 10, 25]

    private enum Key {
        static let idleInterval = "idleInterval"
        static let nudgeDistance = "nudgeDistance"
        static let isEnabled = "isEnabled"
    }

    static func load() -> Settings {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.idleInterval: 60.0,
            Key.nudgeDistance: 10,
            Key.isEnabled: true,
        ])
        return Settings(
            idleInterval: defaults.double(forKey: Key.idleInterval),
            nudgeDistance: defaults.integer(forKey: Key.nudgeDistance),
            isEnabled: defaults.bool(forKey: Key.isEnabled)
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(idleInterval, forKey: Key.idleInterval)
        defaults.set(nudgeDistance, forKey: Key.nudgeDistance)
        defaults.set(isEnabled, forKey: Key.isEnabled)
    }

    /// Human-readable form of an interval, for menu titles.
    static func label(forInterval interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds) seconds" }
        let minutes = seconds / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
