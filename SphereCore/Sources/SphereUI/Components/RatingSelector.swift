import SwiftUI

/// A one-tap 1–N rating row (energy, meal quality, mood…). Highlights the
/// current value and reports taps. Keeps daily logs to a single tap — the
/// anti-fatigue core of the daily loop.
public struct RatingSelector: View {
    private let title: String
    private let systemImage: String
    private let range: ClosedRange<Int>
    private let selection: Int?
    private let tint: Color
    private let onSelect: (Int) -> Void

    @State private var tapTick = 0

    public init(
        title: String,
        systemImage: String,
        range: ClosedRange<Int> = 1...5,
        selection: Int?,
        tint: Color,
        onSelect: @escaping (Int) -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.range = range
        self.selection = selection
        self.tint = tint
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
            HStack(spacing: 8) {
                ForEach(Array(range), id: \.self) { value in
                    Button {
                        tapTick += 1
                        onSelect(value)
                    } label: {
                        Text("\(value)")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                selection == value ? tint : Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(selection == value ? .white : .primary)
                            .scaleEffect(selection == value ? 1.08 : 1)
                            .sphereAnimation(SphereMotion.snappy, value: selection == value)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sphereHaptic(.success, trigger: tapTick)
    }
}
