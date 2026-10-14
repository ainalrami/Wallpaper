import Foundation

/// Preset periods offered for automatic changes.
public enum IntervalPreset {
    public static let all: [TimeInterval] = [
        60, 5 * 60, 15 * 60, 30 * 60, 60 * 60, 3 * 3600, 6 * 3600, 12 * 3600, 24 * 3600, 7 * 24 * 3600,
    ]

    public static func title(for interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.weekOfMonth, .day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "\(Int(interval)) seconds"
    }
}

/// When automatic changes happen.
public enum RotationSchedule {
    /// The shortest period allowed, so a bad value can't change the wallpaper constantly.
    public static let minimumInterval: TimeInterval = 60

    /// When the next change is due, counted from the previous change.
    public static func nextChange(after lastChange: Date?, interval: TimeInterval, now: Date) -> Date {
        guard let lastChange else { return now }
        return lastChange.addingTimeInterval(max(interval, minimumInterval))
    }

    public static func isDue(lastChange: Date?, interval: TimeInterval, now: Date) -> Bool {
        nextChange(after: lastChange, interval: interval, now: now) <= now
    }
}
