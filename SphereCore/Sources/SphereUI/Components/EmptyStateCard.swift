import SwiftUI
import SphereCore

/// Whole-screen "nothing logged yet" coaching card. Shown at the top of a
/// sphere screen when its primary collections are empty, in place of a bare
/// row of zero-data sections. One friendly line of guidance plus a single
/// button that opens the screen's main add-flow — never a dead end.
public struct EmptyStateCard: View {
    private let emoji: String
    private let accent: Color
    private let title: String
    private let message: String
    private let buttonLabel: String
    private let action: () -> Void

    @State private var appeared = false

    public init(
        emoji: String,
        accent: Color,
        title: String,
        message: String,
        buttonLabel: String,
        action: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.accent = accent
        self.title = title
        self.message = message
        self.buttonLabel = buttonLabel
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 48))
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text(buttonLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .frame(maxWidth: .infinity)
        .sphereCard()
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
        .sphereAnimation(SphereMotion.gentle, value: appeared)
        .onAppear { appeared = true }
    }
}
