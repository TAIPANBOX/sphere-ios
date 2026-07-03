import SwiftUI
import SphereCore

/// Sphere accent colours (iOS system palette, mirrors the Flutter AppColors).
/// The full design system lands in Phase 2; screens only need `accent(for:)`
/// and the card style below.
public enum SphereTheme {
    public static func accent(for sphere: SphereType) -> Color {
        switch sphere {
        case .health: Color(hex: 0xFF2D55)
        case .learning: Color(hex: 0x007AFF)
        case .career: Color(hex: 0xFF9500)
        case .finance: Color(hex: 0x34C759)
        case .relationships: Color(hex: 0xAF52DE)
        case .rest: Color(hex: 0x5AC8FA)
        case .hobbies: Color(hex: 0xFF6B35)
        case .travel: Color(hex: 0x30B0C7)
        case .mindfulness: Color(hex: 0xBF5AF2)
        case .creativity: Color(hex: 0xFF375F)
        case .home: Color(hex: 0xFFD60A)
        case .goals: Color(hex: 0x0A84FF)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func sphereCard() -> some View {
        modifier(CardBackground())
    }
}
