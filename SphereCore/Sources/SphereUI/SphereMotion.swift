import SwiftUI

/// Named motion presets for the whole app: no ad-hoc `Animation` values at
/// call sites. Pick a case, apply via `.sphereAnimation(_:value:)`, and Reduce
/// Motion is handled for free (falls back to a short, plain fade).
public enum SphereMotion {
    /// Taps, toggles, counters — quick feedback, ~0.25s.
    public static let snappy: Animation = .spring(response: 0.25, dampingFraction: 0.75)
    /// Cards, list changes, appearance — soft settle, ~0.35s.
    public static let gentle: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    /// Reserved for the rings fill on first appear — bouncier, more presence.
    public static let celebrate: Animation = .spring(response: 0.5, dampingFraction: 0.65)

    /// Plain, short fallback used under Reduce Motion in place of any of the
    /// presets above.
    fileprivate static let reduced: Animation = .easeInOut(duration: 0.2)

    /// `preset` under normal conditions, or the reduced fallback when the
    /// user has Reduce Motion on.
    public static func resolve(_ preset: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : preset
    }
}

extension View {
    /// Animates `value` with a `SphereMotion` preset, automatically degrading
    /// to a short fade under Reduce Motion. The one call site every view
    /// should use instead of a bare `.animation(_:value:)`.
    public func sphereAnimation<V: Equatable>(_ preset: Animation, value: V) -> some View {
        modifier(SphereAnimationModifier(preset: preset, value: value))
    }
}

private struct SphereAnimationModifier<V: Equatable>: ViewModifier {
    let preset: Animation
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(SphereMotion.resolve(preset, reduceMotion: reduceMotion), value: value)
    }
}

/// Semantic haptic cases for `.sphereHaptic`. Kept small on purpose — add a
/// case only when a genuinely new feedback shape is needed.
public enum SphereHaptic {
    case tap
    case success
    case warning
}

extension View {
    /// Fires a semantic haptic when `trigger` changes. No-op on non-iOS
    /// (SphereUI also builds for macOS) and respects the system's own
    /// reduce-motion-driven haptic settings via `.sensoryFeedback` itself.
    @ViewBuilder
    public func sphereHaptic<T: Equatable>(_ haptic: SphereHaptic, trigger: T) -> some View {
        #if os(iOS)
        switch haptic {
        case .tap:
            self.sensoryFeedback(.selection, trigger: trigger)
        case .success:
            self.sensoryFeedback(.success, trigger: trigger)
        case .warning:
            self.sensoryFeedback(.warning, trigger: trigger)
        }
        #else
        self
        #endif
    }
}
