import Foundation

/// Pure helpers for turning imported device reminders into Career tasks while
/// skipping anyone already tracked as an open task. Mirrors `ContactImport`.
public enum ReminderImport {
    /// Which imported reminders aren't yet an open task (matched by trimmed,
    /// case-insensitive title against `existingTitles`, expected to be the
    /// titles of the sphere's open — not done — tasks).
    public static func newTasks(
        from imported: [ImportedReminder], existingTitles: [String]
    ) -> [ImportedReminder] {
        let existing = Set(existingTitles.map(normalized))
        var seen = Set<String>()
        return imported.filter { candidate in
            let key = normalized(candidate.title)
            guard !key.isEmpty, !existing.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    public static func makeTask(from imported: ImportedReminder, now: Date = Date()) -> CareerTask {
        CareerTask(
            id: CareerTask.newID(now: now),
            title: imported.title,
            dueDate: imported.dueDate,
            createdAt: now
        )
    }

    private static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
