import SwiftUI
import SphereCore
import SphereUI

/// Full profile editor — the shared context every agent reads. Changes are
/// debounced into the ProfileStore; birthday edits refresh notifications.
struct ProfileScreen: View {
    let container: AppContainer

    @State private var name = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date()
    @State private var gender: Gender?
    @State private var heightText = ""
    @State private var bloodType: BloodType?
    @State private var hasChildren: Bool?
    @State private var dietary: Set<String> = []
    @State private var allergies: Set<String> = []
    @State private var conditions: Set<String> = []
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Personal") {
                TextField("First name", text: $name)
                TextField("Last name", text: $lastName)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Toggle("Birthday", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker("Date", selection: $birthDate, displayedComponents: .date)
                }
            }

            Section("Body") {
                Picker("Gender", selection: $gender) {
                    Text("—").tag(Gender?.none)
                    ForEach(Gender.allCases, id: \.self) { Text($0.label).tag(Gender?.some($0)) }
                }
                TextField("Height, cm", text: $heightText)
                    .keyboardType(.numberPad)
                Picker("Blood type", selection: $bloodType) {
                    Text("—").tag(BloodType?.none)
                    ForEach(BloodType.allCases, id: \.self) { Text($0.label).tag(BloodType?.some($0)) }
                }
                Picker("Children", selection: $hasChildren) {
                    Text("—").tag(Bool?.none)
                    Text("Yes").tag(Bool?.some(true))
                    Text("No").tag(Bool?.some(false))
                }
            }

            Section("Dietary restrictions") {
                ChipGrid(options: ProfileOptions.dietary, tint: .green, selected: $dietary)
            }
            Section("Food allergies") {
                ChipGrid(options: ProfileOptions.allergies, tint: .red, selected: $allergies)
            }
            Section {
                ChipGrid(options: ProfileOptions.conditions, tint: .orange, selected: $conditions)
            } header: {
                Text("Health conditions")
            } footer: {
                Text("Everything here flows into every agent's context — "
                    + "dietary tags shape Travel advice, conditions shape Health advice.")
            }
        }
        .navigationTitle("Profile")
        .onAppear(perform: loadIntoForm)
        .onDisappear { Task { await persist() } }
    }

    private func loadIntoForm() {
        guard !loaded else { return }
        loaded = true
        let p = container.profile.profile
        name = p.name
        lastName = p.lastName
        email = p.email
        if let bd = p.birthDate { hasBirthDate = true; birthDate = bd }
        gender = p.gender
        heightText = p.heightCm.map { String(Int($0)) } ?? ""
        bloodType = p.bloodType
        hasChildren = p.hasChildren
        dietary = Set(p.dietaryRestrictions)
        allergies = Set(p.foodAllergies)
        conditions = Set(p.healthConditions)
    }

    private func persist() async {
        let hadBirthday = container.profile.profile.birthDate
        try? await container.profile.update { p in
            p.name = name.trimmingCharacters(in: .whitespaces)
            p.lastName = lastName.trimmingCharacters(in: .whitespaces)
            p.email = email.trimmingCharacters(in: .whitespaces)
            p.birthDate = hasBirthDate ? birthDate : nil
            p.gender = gender
            p.heightCm = Double(heightText.filter(\.isNumber))
            p.bloodType = bloodType
            p.hasChildren = hasChildren
            p.dietaryRestrictions = ProfileOptions.dietary.map(\.value).filter(dietary.contains)
            p.foodAllergies = ProfileOptions.allergies.map(\.value).filter(allergies.contains)
            p.healthConditions = ProfileOptions.conditions.map(\.value).filter(conditions.contains)
        }
        // The user's own birthday isn't a contact reminder, but editing the
        // profile is a natural place to keep contact reminders fresh too.
        if container.profile.profile.birthDate != hadBirthday {
            await container.refreshBirthdayReminders()
        }
    }
}
