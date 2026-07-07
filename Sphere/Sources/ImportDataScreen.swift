import SwiftUI
import SphereCore

/// Settings → "Import from device": one screen to pull Apple Health,
/// Contacts, and Calendar & Reminders data in, replacing the old first-run
/// "Connect Apple Health" card on the Health screen (which could render
/// invisible — see docs/BACKLOG.md). Each row's action is idempotent, so
/// re-running an import never duplicates data.
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
                    caption: "Steps, heart rate, sleep, cycle, workouts and weight — "
                        + "nothing leaves your device.",
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
                    title: "Calendar & Reminders",
                    caption: "Today's events for your morning brief, plus open "
                        + "reminders into Career tasks.",
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
        let nights = await container.rest.importSleepFromHealth(days: 90)
        let cycles = await container.health.importCycleFromHealth()
        let workouts = await container.health.importWorkoutsFromHealth()
        let weighIns = await container.health.importWeightsFromHealth()

        var parts: [String] = []
        if workouts > 0 { parts.append("\(workouts) workout\(workouts == 1 ? "" : "s")") }
        if weighIns > 0 { parts.append("\(weighIns) weigh-in\(weighIns == 1 ? "" : "s")") }
        if nights > 0 { parts.append("\(nights) night\(nights == 1 ? "" : "s") of sleep") }
        if cycles > 0 { parts.append("\(cycles) cycle\(cycles == 1 ? "" : "s")") }

        healthState = .done(
            parts.isEmpty ? "Connected. Nothing new to import." : "Connected. Imported \(parts.joined(separator: ", "))."
        )
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

    // MARK: - Calendar & Reminders

    private func importCalendar() async {
        calendarState = .running
        let calendarGranted = await container.eventKit.requestAccess()
        if calendarGranted {
            await container.home.refreshCalendar()
        }
        let reminders = await container.career.importRemindersFromDevice()

        let base = calendarGranted ? "Calendar connected" : "Calendar access declined"
        calendarState = .done("\(base) · \(reminders) reminder\(reminders == 1 ? "" : "s") imported.")
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
