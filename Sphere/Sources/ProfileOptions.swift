import SwiftUI
import SphereCore
import SphereUI

/// Selectable option catalogues, mirroring the Flutter onboarding/profile
/// chips. Value strings are what get persisted and fed to agents.
enum ProfileOptions {
    static let dietary: [(value: String, emoji: String, label: String)] = [
        ("vegan", "🌱", "Vegan"),
        ("vegetarian", "🥗", "Vegetarian"),
        ("gluten_free", "🌾", "Gluten-free"),
        ("lactose_free", "🥛", "Lactose-free"),
        ("halal", "🕌", "Halal"),
        ("kosher", "✡️", "Kosher"),
    ]

    static let allergies: [(value: String, emoji: String, label: String)] = [
        ("nuts", "🥜", "Nuts"),
        ("seafood", "🦐", "Seafood"),
        ("eggs", "🥚", "Eggs"),
        ("dairy", "🧀", "Dairy"),
        ("soy", "🫛", "Soy"),
        ("shellfish", "🦀", "Shellfish"),
    ]

    static let conditions: [(value: String, emoji: String, label: String)] = [
        ("hypertension", "🩸", "Hypertension"),
        ("diabetes", "💉", "Diabetes"),
        ("asthma", "🫁", "Asthma"),
        ("hypothyroidism", "🦋", "Hypothyroidism"),
        ("anxiety", "🌀", "Anxiety"),
        ("migraine", "🤕", "Migraine"),
    ]
}

/// Wrapping grid of toggleable chips backed by a `Set<String>` binding.
struct ChipGrid: View {
    let options: [(value: String, emoji: String, label: String)]
    let tint: Color
    @Binding var selected: Set<String>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.value) { option in
                let isOn = selected.contains(option.value)
                Button {
                    if isOn { selected.remove(option.value) } else { selected.insert(option.value) }
                } label: {
                    (Text(option.emoji) + Text(" ") + Text(LocalizedStringKey(option.label)))
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isOn ? tint.opacity(0.18) : Color.secondary.opacity(0.1),
                            in: Capsule()
                        )
                        .foregroundStyle(isOn ? tint : .primary)
                        .overlay(
                            Capsule().strokeBorder(isOn ? tint : .clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
