import Foundation

public enum Gender: String, Codable, CaseIterable, Sendable {
    case male, female, other, preferNotToSay

    public var label: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        case .preferNotToSay: "Prefer not to say"
        }
    }
}

public enum BloodType: String, Codable, CaseIterable, Sendable {
    case aPos, aNeg, bPos, bNeg, abPos, abNeg, oPos, oNeg

    public var label: String {
        switch self {
        case .aPos: "A+"
        case .aNeg: "A−"
        case .bPos: "B+"
        case .bNeg: "B−"
        case .abPos: "AB+"
        case .abNeg: "AB−"
        case .oPos: "O+"
        case .oNeg: "O−"
        }
    }
}

/// The shared context layer every agent sees. `agentContext` is the compact
/// summary woven into each sphere agent's system prompt (via
/// `AgentService.chat(userContext:)`), so dietary restrictions shape Travel
/// advice, conditions shape Health advice, and every agent addresses the
/// user by name. Ported from the Flutter `UserProfile`.
public struct UserProfile: Codable, Equatable, Sendable {
    public var name: String
    public var lastName: String
    public var email: String
    public var birthDate: Date?
    public var hasChildren: Bool?
    public var gender: Gender?
    public var heightCm: Double?
    public var bloodType: BloodType?

    /// vegan, vegetarian, gluten_free, lactose_free, halal, kosher …
    public var dietaryRestrictions: [String]
    /// nuts, seafood, eggs, dairy, shellfish …
    public var foodAllergies: [String]
    /// diabetes, hypertension, asthma …
    public var healthConditions: [String]

    /// Enabled spheres. Empty means all 12 are active (Dart semantics).
    public var activeSpheres: [String]

    /// Set once onboarding completes; gates the first-launch flow.
    public var onboarded: Bool

    public init(
        name: String = "",
        lastName: String = "",
        email: String = "",
        birthDate: Date? = nil,
        hasChildren: Bool? = nil,
        gender: Gender? = nil,
        heightCm: Double? = nil,
        bloodType: BloodType? = nil,
        dietaryRestrictions: [String] = [],
        foodAllergies: [String] = [],
        healthConditions: [String] = [],
        activeSpheres: [String] = [],
        onboarded: Bool = false
    ) {
        self.name = name
        self.lastName = lastName
        self.email = email
        self.birthDate = birthDate
        self.hasChildren = hasChildren
        self.gender = gender
        self.heightCm = heightCm
        self.bloodType = bloodType
        self.dietaryRestrictions = dietaryRestrictions
        self.foodAllergies = foodAllergies
        self.healthConditions = healthConditions
        self.activeSpheres = activeSpheres
        self.onboarded = onboarded
    }

    public var fullName: String {
        let parts = [name, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return parts.isEmpty ? "User" : parts
    }

    public var initials: String {
        let first = name.first.map { String($0).uppercased() } ?? ""
        let last = lastName.first.map { String($0).uppercased() } ?? ""
        let result = first + last
        return result.isEmpty ? "U" : result
    }

    public func age(asOf now: Date = Date()) -> Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: now).year
    }

    /// True when `sphere` should be shown/active (empty list = all active).
    public func isSphereActive(_ sphere: SphereType) -> Bool {
        activeSpheres.isEmpty || activeSpheres.contains(sphere.rawValue)
    }

    /// Compact multi-line summary for agent system prompts.
    public func agentContext(asOf now: Date = Date()) -> String {
        var parts: [String] = []
        if !name.isEmpty { parts.append("User name: \(name)") }
        if let age = age(asOf: now) { parts.append("Age: \(age)") }
        if let gender { parts.append("Gender: \(gender.rawValue)") }
        if let heightCm { parts.append("Height: \(Int(heightCm)) cm") }
        if !dietaryRestrictions.isEmpty {
            parts.append("Dietary: \(dietaryRestrictions.joined(separator: ", "))")
        }
        if !foodAllergies.isEmpty {
            parts.append("Allergies: \(foodAllergies.joined(separator: ", "))")
        }
        if !healthConditions.isEmpty {
            parts.append("Health conditions: \(healthConditions.joined(separator: ", "))")
        }
        if let bloodType { parts.append("Blood type: \(bloodType.label)") }
        if let hasChildren { parts.append(hasChildren ? "Has children" : "No children") }
        return parts.joined(separator: "\n")
    }
}
