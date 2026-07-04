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

/// How the user wants streaks and pressure handled right now. `sick`/
/// `vacation` pause all streaks and soften the Life Score (forgiveness, N4).
public enum WellbeingMode: String, Codable, CaseIterable, Sendable {
    case normal, sick, vacation

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .sick: "Sick"
        case .vacation: "Vacation"
        }
    }
}

/// The shared context layer every agent sees. `agentContext` is the compact
/// summary woven into each sphere agent's system prompt (via
/// `AgentService.chat(userContext:)`), so dietary restrictions shape Travel
/// advice, conditions shape Health advice, and every agent addresses the
/// user by name. Ported from the Flutter `UserProfile`.
///
/// Persisted as a single JSON blob, so decoding is deliberately tolerant
/// (`decodeIfPresent` for every field) — new fields never break an older
/// stored profile, and no GRDB migration is needed to add one.
public struct UserProfile: Codable, Equatable, Sendable {
    public var name: String
    public var lastName: String
    public var email: String
    public var birthDate: Date?
    public var hasChildren: Bool?
    public var gender: Gender?
    public var heightCm: Double?
    public var bloodType: BloodType?

    /// Free-text self-description — the highest-value single field for agent
    /// context (goals, personality, situation the user chooses to share).
    public var aboutMe: String
    /// Home city; weather fallback when location is denied + travel/local context.
    public var city: String

    /// vegan, vegetarian, gluten_free, lactose_free, halal, kosher …
    public var dietaryRestrictions: [String]
    /// nuts, seafood, eggs, dairy, shellfish …
    public var foodAllergies: [String]
    /// diabetes, hypertension, asthma …
    public var healthConditions: [String]

    /// Enabled spheres. Empty means all 12 are active (Dart semantics).
    public var activeSpheres: [String]

    /// User's preferred sphere order on the grid. Empty = default enum order;
    /// unknown/missing spheres fall back to the end in enum order.
    public var sphereOrder: [String]

    /// Set once onboarding completes; gates the first-launch flow.
    public var onboarded: Bool

    // MARK: profile-v2 (Stage 1)

    /// Per-category notification opt-in ("water", "medication", "bedtime",
    /// "plant", "subscription", "morningBrief", "nudge", "birthday" …).
    /// Missing key falls back to each category's own default.
    public var notificationPrefs: [String: Bool]

    /// Forgiveness mode: pauses streaks / softens Life Score until `until`.
    public var wellbeingMode: WellbeingMode
    public var wellbeingUntil: Date?
    /// When the current sick/vacation mode began (bounds the excused-day set).
    public var wellbeingSince: Date?

    /// Annual paid-time-off allowance (Rest vacation ledger).
    public var vacationDaysPerYear: Int?

    /// Mirror of the Face ID app-lock toggle, so it travels in data export.
    public var appLockEnabled: Bool

    public init(
        name: String = "",
        lastName: String = "",
        email: String = "",
        birthDate: Date? = nil,
        hasChildren: Bool? = nil,
        gender: Gender? = nil,
        heightCm: Double? = nil,
        bloodType: BloodType? = nil,
        aboutMe: String = "",
        city: String = "",
        dietaryRestrictions: [String] = [],
        foodAllergies: [String] = [],
        healthConditions: [String] = [],
        activeSpheres: [String] = [],
        sphereOrder: [String] = [],
        onboarded: Bool = false,
        notificationPrefs: [String: Bool] = [:],
        wellbeingMode: WellbeingMode = .normal,
        wellbeingUntil: Date? = nil,
        wellbeingSince: Date? = nil,
        vacationDaysPerYear: Int? = nil,
        appLockEnabled: Bool = false
    ) {
        self.name = name
        self.lastName = lastName
        self.email = email
        self.birthDate = birthDate
        self.hasChildren = hasChildren
        self.gender = gender
        self.heightCm = heightCm
        self.bloodType = bloodType
        self.aboutMe = aboutMe
        self.city = city
        self.dietaryRestrictions = dietaryRestrictions
        self.foodAllergies = foodAllergies
        self.healthConditions = healthConditions
        self.activeSpheres = activeSpheres
        self.sphereOrder = sphereOrder
        self.onboarded = onboarded
        self.notificationPrefs = notificationPrefs
        self.wellbeingMode = wellbeingMode
        self.wellbeingUntil = wellbeingUntil
        self.wellbeingSince = wellbeingSince
        self.vacationDaysPerYear = vacationDaysPerYear
        self.appLockEnabled = appLockEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case name, lastName, email, birthDate, hasChildren, gender, heightCm
        case bloodType, aboutMe, city
        case dietaryRestrictions, foodAllergies, healthConditions
        case activeSpheres, sphereOrder, onboarded
        case notificationPrefs, wellbeingMode, wellbeingUntil, wellbeingSince
        case vacationDaysPerYear, appLockEnabled
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        birthDate = try c.decodeIfPresent(Date.self, forKey: .birthDate)
        hasChildren = try c.decodeIfPresent(Bool.self, forKey: .hasChildren)
        gender = try c.decodeIfPresent(Gender.self, forKey: .gender)
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm)
        bloodType = try c.decodeIfPresent(BloodType.self, forKey: .bloodType)
        aboutMe = try c.decodeIfPresent(String.self, forKey: .aboutMe) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        dietaryRestrictions = try c.decodeIfPresent([String].self, forKey: .dietaryRestrictions) ?? []
        foodAllergies = try c.decodeIfPresent([String].self, forKey: .foodAllergies) ?? []
        healthConditions = try c.decodeIfPresent([String].self, forKey: .healthConditions) ?? []
        activeSpheres = try c.decodeIfPresent([String].self, forKey: .activeSpheres) ?? []
        sphereOrder = try c.decodeIfPresent([String].self, forKey: .sphereOrder) ?? []
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        notificationPrefs = try c.decodeIfPresent([String: Bool].self, forKey: .notificationPrefs) ?? [:]
        wellbeingMode = try c.decodeIfPresent(WellbeingMode.self, forKey: .wellbeingMode) ?? .normal
        wellbeingUntil = try c.decodeIfPresent(Date.self, forKey: .wellbeingUntil)
        wellbeingSince = try c.decodeIfPresent(Date.self, forKey: .wellbeingSince)
        vacationDaysPerYear = try c.decodeIfPresent(Int.self, forKey: .vacationDaysPerYear)
        appLockEnabled = try c.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
    }

    /// Active spheres in the user's saved order. Any sphere absent from
    /// `sphereOrder` (newly enabled, or all when order is empty) trails in
    /// the default enum order, so the grid never drops a sphere.
    public var orderedActiveSpheres: [SphereType] {
        let ranked = sphereOrder.enumerated().reduce(into: [String: Int]()) { $0[$1.element] = $1.offset }
        let enumIndex = SphereType.allCases.enumerated()
            .reduce(into: [SphereType: Int]()) { $0[$1.element] = $1.offset }
        return SphereType.allCases
            .filter(isSphereActive)
            .sorted {
                (ranked[$0.rawValue] ?? .max, enumIndex[$0] ?? 0)
                    < (ranked[$1.rawValue] ?? .max, enumIndex[$1] ?? 0)
            }
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

    /// True while the user is in sick/vacation mode and it hasn't expired —
    /// streaks pause and the Life Score softens (forgiveness, N4).
    public func isWellbeingPaused(asOf now: Date = Date()) -> Bool {
        guard wellbeingMode != .normal else { return false }
        if let wellbeingUntil { return now <= wellbeingUntil }
        return true
    }

    /// Notification opt-in for a category, honoring the stored preference and
    /// falling back to that category's own default when unset.
    public func notificationEnabled(_ category: String, default fallback: Bool) -> Bool {
        notificationPrefs[category] ?? fallback
    }

    /// Day keys covered by the current pause (sick/vacation) — these bridge
    /// streaks so a missed day during recovery doesn't reset them. Empty when
    /// not paused. Capped so a stale/very old `since` can't explode the set.
    public func wellbeingExcusedDays(asOf now: Date = Date(), maxDays: Int = 90) -> Set<String> {
        guard isWellbeingPaused(asOf: now) else { return [] }
        let calendar = DayKey.calendar
        let today = calendar.startOfDay(for: now)
        let end = min(wellbeingUntil.map(calendar.startOfDay(for:)) ?? today, today)
        let start = wellbeingSince.map(calendar.startOfDay(for:)) ?? end
        var keys: Set<String> = []
        var day = min(start, end)
        var guardCount = 0
        while day <= end, guardCount < maxDays {
            keys.insert(DayKey.make(day))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(86_400)
            guardCount += 1
        }
        return keys
    }

    /// Compact multi-line summary for agent system prompts.
    public func agentContext(asOf now: Date = Date()) -> String {
        var parts: [String] = []
        if !name.isEmpty { parts.append("User name: \(name)") }
        if let age = age(asOf: now) { parts.append("Age: \(age)") }
        if let gender { parts.append("Gender: \(gender.rawValue)") }
        if !city.isEmpty { parts.append("City: \(city)") }
        if let heightCm { parts.append("Height: \(Int(heightCm)) cm") }
        if !aboutMe.isEmpty { parts.append("About: \(aboutMe)") }
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
