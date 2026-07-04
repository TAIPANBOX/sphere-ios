import SwiftUI
import SphereCore
import SphereUI

/// First-launch setup: welcome → personal info → dietary → sphere selection.
/// On finish, writes the profile with `onboarded = true`, which flips the
/// app to the main shell.
struct OnboardingFlow: View {
    let container: AppContainer

    @State private var step = 0
    @State private var name = ""
    @State private var email = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Calendar.current.date(from: DateComponents(year: 1995, month: 1, day: 1))!
    @State private var dietary: Set<String> = []
    @State private var allergies: Set<String> = []
    @State private var disabledSpheres: Set<SphereType> = []
    @State private var saving = false

    private let accent = SphereTheme.accent(for: .goals)

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: 4)
                .tint(accent)
                .padding()

            TabView(selection: $step) {
                welcomeStep.tag(0)
                personalStep.tag(1)
                dietaryStep.tag(2)
                spheresStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            footer
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🌐").font(.system(size: 80))
            Text("Welcome to Sphere")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("An AI companion for all 12 spheres of your life — each with "
                + "its own agent that remembers everything, on your device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var personalStep: some View {
        Form {
            Section {
                TextField("First name", text: $name)
                TextField("Email (optional)", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Toggle("Add birthday", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker("Birthday", selection: $birthDate, displayedComponents: .date)
                }
            } header: {
                Text("About you")
            } footer: {
                Text("Every agent addresses you by name and weaves these "
                    + "details into its memory.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var dietaryStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Dietary preferences")
                    .font(.title2.weight(.bold))
                Text("These shape Health and Travel recommendations. Skip if "
                    + "none apply.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Restrictions").font(.headline)
                ChipGrid(options: ProfileOptions.dietary, tint: .green, selected: $dietary)

                Text("Allergies").font(.headline)
                ChipGrid(options: ProfileOptions.allergies, tint: .red, selected: $allergies)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var spheresStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose your spheres")
                    .font(.title2.weight(.bold))
                Text("Tap to turn any off — you can change this anytime in "
                    + "Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(SphereType.allCases, id: \.self) { sphere in
                        let on = !disabledSpheres.contains(sphere)
                        Button {
                            if on { disabledSpheres.insert(sphere) } else { disabledSpheres.remove(sphere) }
                        } label: {
                            HStack {
                                Text(sphere.rawValue.capitalized)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? SphereTheme.accent(for: sphere) : .secondary)
                            }
                            .padding(12)
                            .background(
                                SphereTheme.accent(for: sphere).opacity(on ? 0.12 : 0.04),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(step == 3 ? "Get started" : "Continue") {
                if step < 3 {
                    step += 1
                } else {
                    Task { await finish() }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(step == 1 && name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
        }
        .padding()
    }

    private func finish() async {
        saving = true
        let active = SphereType.allCases
            .filter { !disabledSpheres.contains($0) }
            .map(\.rawValue)
        try? await container.profile.save(UserProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            birthDate: hasBirthDate ? birthDate : nil,
            dietaryRestrictions: ProfileOptions.dietary.map(\.value).filter(dietary.contains),
            foodAllergies: ProfileOptions.allergies.map(\.value).filter(allergies.contains),
            activeSpheres: active.count == SphereType.allCases.count ? [] : active,
            onboarded: true
        ))
    }
}
