import SwiftUI
import SphereCore
import SphereUI
import PhotosUI

/// Full profile editor — the shared context every agent reads. Changes persist
/// on exit and on backgrounding; birthday edits refresh notifications.
struct ProfileScreen: View {
    let container: AppContainer

    @Environment(\.scenePhase) private var scenePhase
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?

    @State private var name = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date()
    @State private var gender: Gender?
    @State private var heightText = ""
    @State private var bloodType: BloodType?
    @State private var hasChildren: Bool?
    @State private var city = ""
    @State private var aboutMe = ""
    @State private var dietary: Set<String> = []
    @State private var allergies: Set<String> = []
    @State private var conditions: Set<String> = []
    @State private var wellbeing = WellbeingMode.normal
    @State private var hasWellbeingUntil = false
    @State private var wellbeingUntil = Date()
    @State private var loaded = false
    @State private var showingRecap = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        avatarView
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(hasAvatar ? "Change photo" : "Add photo")
                        }
                        if hasAvatar {
                            Button("Remove", role: .destructive, action: removeAvatar)
                                .font(.caption)
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    showingRecap = true
                } label: {
                    HStack(spacing: 12) {
                        Text("✨").font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your Year in Sphere").font(.body.weight(.medium))
                            Text("A shareable recap across every sphere.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }

            Section("Personal") {
                TextField("First name", text: $name)
                TextField("Last name", text: $lastName)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("City", text: $city)
                Toggle("Birthday", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker("Date", selection: $birthDate, displayedComponents: .date)
                }
            }

            Section {
                TextField("A few words about you, your goals, your situation…",
                          text: $aboutMe, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("About me")
            } footer: {
                Text("The most useful thing you can tell your agents. Shared with "
                    + "every sphere so advice fits your life.")
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

            Section {
                Picker("Mode", selection: $wellbeing) {
                    ForEach(WellbeingMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if wellbeing != .normal {
                    Toggle("Set an end date", isOn: $hasWellbeingUntil)
                    if hasWellbeingUntil {
                        DatePicker("Until", selection: $wellbeingUntil, displayedComponents: .date)
                    }
                }
            } header: {
                Text("Wellbeing")
            } footer: {
                Text("Sick or vacation mode pauses your streaks and mutes daily "
                    + "nudges, so a break never costs you your progress.")
            }
            .onChange(of: wellbeing) { _, _ in applyWellbeing() }
            .onChange(of: hasWellbeingUntil) { _, _ in applyWellbeing() }
            .onChange(of: wellbeingUntil) { _, _ in applyWellbeing() }

            Section {
                let context = container.profile.profile.agentContext()
                if context.isEmpty {
                    Text("Nothing yet — fill in the fields above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(context)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Label("What your agents know about you", systemImage: "eye")
            } footer: {
                Text("This is the entire context shared with your agents — nothing "
                    + "else about you leaves this device. Updates when you save.")
            }
        }
        .navigationTitle("Profile")
        .sheet(isPresented: $showingRecap) {
            let year = container.recap.currentYear()
            YearInSphereScreen(cards: container.recap.cards(year: year), stats: container.recap.stats(year: year))
        }
        .onAppear {
            loadIntoForm()
            avatarImage = AvatarStorage.image
        }
        .onChange(of: photoItem) { _, item in loadAvatar(item) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await persist() } }
        }
        .onDisappear { Task { await persist() } }
    }

    @ViewBuilder private var avatarView: some View {
        if let avatarImage {
            Image(uiImage: avatarImage)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 84, height: 84)
                .overlay(Text(container.profile.profile.initials).font(.title.weight(.semibold)))
        }
    }

    private var hasAvatar: Bool { avatarImage != nil }

    private func loadAvatar(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                AvatarStorage.save(data)
                avatarImage = AvatarStorage.image
            }
        }
    }

    private func removeAvatar() {
        AvatarStorage.clear()
        avatarImage = nil
        photoItem = nil
    }

    private func applyWellbeing() {
        guard loaded else { return }
        let until = (wellbeing != .normal && hasWellbeingUntil) ? wellbeingUntil : nil
        Task { await container.setWellbeing(wellbeing, until: until) }
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
        city = p.city
        aboutMe = p.aboutMe
        dietary = Set(p.dietaryRestrictions)
        allergies = Set(p.foodAllergies)
        conditions = Set(p.healthConditions)
        wellbeing = p.wellbeingMode
        if let until = p.wellbeingUntil { hasWellbeingUntil = true; wellbeingUntil = until }
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
            p.city = city.trimmingCharacters(in: .whitespaces)
            p.aboutMe = aboutMe.trimmingCharacters(in: .whitespaces)
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
