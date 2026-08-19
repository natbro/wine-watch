import Foundation

enum Preferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let interval = "refreshInterval"
        static let greenWhenClear = "showGreenBadgeWhenClear"
    }

    /// Seconds between sweeps of the process table.
    static var refreshInterval: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.interval)
            return allowedIntervals.contains(stored) ? stored : 4
        }
        set { defaults.set(newValue, forKey: Key.interval) }
    }

    static let allowedIntervals: [TimeInterval] = [3, 4, 5]

    /// When nothing is running, show a green "0" instead of a bare glass.
    static var showGreenBadgeWhenClear: Bool {
        get { defaults.bool(forKey: Key.greenWhenClear) }
        set { defaults.set(newValue, forKey: Key.greenWhenClear) }
    }
}
