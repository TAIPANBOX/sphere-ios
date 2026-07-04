import Foundation

/// A contact pulled from the device address book, flattened so the mapping
/// stays Contacts-framework-free and testable.
public struct ImportedContact: Sendable, Equatable, Identifiable {
    /// Stable device identifier (dedupes across imports).
    public let id: String
    public let name: String
    public let birthday: Date?

    public init(id: String, name: String, birthday: Date? = nil) {
        self.id = id
        self.name = name
        self.birthday = birthday
    }
}

/// Reads the device address book. Lives behind a protocol so SphereCore stays
/// free of the Contacts framework and the import path is testable.
public protocol ContactsProviding: Sendable {
    func requestAccess() async -> Bool
    func fetchContacts() async -> [ImportedContact]
}

/// Pure helpers for turning imported contacts into sphere `Contact`s while
/// skipping anyone already in the sphere.
public enum ContactImport {
    /// Which imported contacts aren't yet in the sphere (matched by trimmed,
    /// case-insensitive name).
    public static func newContacts(
        from imported: [ImportedContact], existing: [Contact]
    ) -> [ImportedContact] {
        let existingNames = Set(existing.map { normalized($0.name) })
        var seen = Set<String>()
        return imported.filter { candidate in
            let key = normalized(candidate.name)
            guard !key.isEmpty, !existingNames.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    public static func makeContact(from imported: ImportedContact, now: Date = Date()) -> Contact {
        Contact(
            id: Contact.newID(now: now),
            name: imported.name,
            birthday: imported.birthday,
            note: "Imported from Contacts"
        )
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
