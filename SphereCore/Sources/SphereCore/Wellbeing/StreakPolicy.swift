import Foundation

/// Forgiveness-aware streak counting (N4). A streak is the run of consecutive
/// days ending today where each day is either *active* (the habit was done) or
/// *excused* (the user was in sick/vacation mode). Excused days bridge the
/// streak — they don't add to it, but they don't break it either — so a missed
/// day during recovery doesn't nuke months of progress.
///
/// Behavior is identical to a plain streak when no days are excused (today not
/// done → 0), so existing call sites keep their semantics until wellbeing days
/// are supplied.
public enum StreakPolicy {
    public static func streak(
        asOf now: Date = Date(),
        maxLookback: Int = 400,
        isActive: (Date) -> Bool,
        isExcused: (Date) -> Bool = { _ in false }
    ) -> Int {
        let calendar = DayKey.calendar
        var day = calendar.startOfDay(for: now)
        var streak = 0
        var steps = 0
        while steps < maxLookback {
            if isActive(day) {
                streak += 1
            } else if isExcused(day) {
                // bridge — neither increment nor break
            } else {
                break
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            steps += 1
        }
        return streak
    }
}
