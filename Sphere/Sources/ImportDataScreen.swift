import SwiftUI
import SphereCore

/// Settings → "Import from device": one screen to pull Apple Health,
/// Contacts, and Calendar data in, replacing the old first-run "Connect
/// Apple Health" card on the Health screen (which could render invisible —
/// see docs/BACKLOG.md). Each row's action is idempotent, so re-running an
/// import never duplicates data.
struct ImportDataScreen: View {
    let container: AppContainer

    @State private var healthState = ImportRowState.idle
    @State private var contactsState = ImportRowState.idle
    @State private var calendarState = ImportRowState.idle

    var body: some View {
        Form {
            Section {
                ImportRow(
                    icon: "heart.fill", tint: .pink,
                    title: "Apple Health",
                    caption: "Steps, heart rate, sleep and cycle — nothing leaves your device.",
                    state: healthState
                ) {
                    await importHealth()
                }
                ImportRow(
                    icon: "person.fill", tint: .purple,
                    title: "Contacts",
                    caption: "Names and birthdays into Relationships.",
                    state: contactsState
                ) {
                    await importContacts()
                }
                ImportRow(
                    icon: "calendar", tint: .orange,
                    title: "Calendar",
                    caption: "Lets your morning brief see today's events.",
                    state: calendarState
                ) {
                    await importCalendar()
                }
            } footer: {
                Text("Everything is imported on-device. You can run these again "
                    + "anytime — nothing is duplicated.")
            }
        }
        .navigationTitle("Import from device")
    }

    // MARK: - Apple Health

    private func importHealth() async {
        healthState = .running
        _ = await container.health.requestHealthAccess()
        await container.health.refreshMetrics()
        let nights = await container.rest.importSleepFromHealth(days: 30)
        let cycles = await container.health.importCycleFromHealth()
        var message = "Connected. Imported \(nights) night\(nights == 1 ? "" : "s") of sleep."
        if cycles > 0 {
            message += " \(cycles) cycle\(cycles == 1 ? "" : "s") logged."
        }
        healthState = .done(message)
    }

    // MARK: - Contacts

    private func importContacts() async {
        contactsState = .running
        let candidates = await container.relationships.importableContacts()
        guard !candidates.isEmpty else {
            contactsState = .done(
                container.relationships.hasContactsProvider
                    ? "No new contacts to import."
                    : "Access declined."
            )
            return
        }
        let added = await container.relationships.importContacts(candidates)
        await container.refreshReminders()
        contactsState = .done("Imported \(added) contact\(added == 1 ? "" : "s").")
    }

    // MARK: - Calendar

    private func importCalendar() async {
        calendarState = .running
        let granted = await EventKitService().requestAccess()
        if granted {
            await container.home.refreshCalendar()
        }
        calendarState = .done(granted ? "Calendar connected." : "Access declined.")
    }
}

/// Per-row import progress: idle → running → done (with a result caption).
private enum ImportRowState: Equatable {
    case idle
    case running
    case done(String)

    var isRunning: Bool { self == .running }

    var resultCaption: String? {
        if case .done(let message) = self { return message }
        return nil
    }
}

private struct ImportRow: View {
    let icon: String
    let tint: Color
    let title: String
    let caption: String
    let state: ImportRowState
    let action: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(caption).font(.caption).foregroundStyle(.secondary)
                if let resultCaption = state.resultCaption {
                    Text(resultCaption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint)
                }
            }
            Spacer()
            if state.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Button("Import") {
                    Task { await action() }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
