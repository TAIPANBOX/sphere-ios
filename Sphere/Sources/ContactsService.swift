#if canImport(Contacts)
import Contacts
import Foundation
import SphereCore

/// Live address-book reader backing `RelationshipsStore` imports. Read-only.
///
/// `@unchecked Sendable`: `CNContactStore` is thread-safe and the class holds
/// no other mutable state.
final class ContactsService: ContactsProviding, @unchecked Sendable {
    private let store = CNContactStore()

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func fetchContacts() async -> [ImportedContact] {
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactBirthdayKey,
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var results: [ImportedContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = "\(contact.givenName) \(contact.familyName)"
                    .trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                var birthday: Date?
                if let components = contact.birthday, components.month != nil,
                   let date = Calendar.current.date(from: components) {
                    birthday = date
                }
                results.append(ImportedContact(
                    id: contact.identifier, name: name, birthday: birthday
                ))
            }
        } catch {
            return results
        }
        return results
    }
}
#endif
