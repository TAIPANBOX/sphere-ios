import Foundation
import GRDB

/// Sphere domain database (goals, habits, transactions, …) — separate file
/// from the Engram memory DB, same GRDB family. Every sphere adds its tables
/// as a new migration below; migrations run in registration order and must
/// never be edited once shipped.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public convenience init(path: String) throws {
        try self.init(writer: DatabasePool(path: path))
    }

    /// In-memory database for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("goals-v1") { db in
            try db.create(table: "goals") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("emoji", .text).notNull().defaults(to: "🎯")
                t.column("horizon", .text).notNull()
                t.column("status", .text).notNull()
                t.column("progressPercent", .integer).notNull().defaults(to: 0)
                t.column("keyResults", .text).notNull().defaults(to: "[]")
                t.column("sphereType", .text)
                t.column("blockedByGoalId", .text)
            }
            try db.create(table: "habits") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull().defaults(to: "✅")
                t.column("checkInDates", .text).notNull().defaults(to: "[]")
            }
        }

        migrator.registerMigration("health-v1") { db in
            try db.create(table: "water") { t in
                t.primaryKey("dateKey", .text)
                t.column("glasses", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "weights") { t in
                t.primaryKey("dateKey", .text)
                t.column("date", .datetime).notNull()
                t.column("kg", .double).notNull()
            }
            try db.create(table: "workouts") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("durationMinutes", .integer).notNull()
                t.column("caloriesBurned", .integer)
                t.column("distanceKm", .double)
                t.column("date", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("finance-v1") { db in
            try db.create(table: "transactions") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("amount", .double).notNull()
                t.column("type", .text).notNull()
                t.column("category", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "budgets") { t in
                t.primaryKey("id", .text)
                t.column("category", .text).notNull()
                t.column("limit", .double).notNull()
            }
            try db.create(table: "subscriptions") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull().defaults(to: "📱")
                t.column("amount", .double).notNull()
                t.column("billingDay", .integer).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
            }
        }

        migrator.registerMigration("health-v2") { db in
            try db.create(table: "medications") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("dosage", .text).notNull().defaults(to: "")
                t.column("frequency", .text).notNull()
                t.column("takenDates", .text).notNull().defaults(to: "[]")
            }
            try db.create(table: "lab_results") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("value", .text).notNull()
                t.column("unit", .text).notNull().defaults(to: "")
                t.column("refRange", .text).notNull().defaults(to: "")
                t.column("date", .datetime).notNull()
                t.column("isNormal", .boolean).notNull().defaults(to: true)
            }
        }

        migrator.registerMigration("finance-v2") { db in
            try db.create(table: "accounts") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("balance", .double).notNull().defaults(to: 0)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "savings_goals") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull().defaults(to: "🎯")
                t.column("target", .double).notNull()
                t.column("saved", .double).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("learning-v1") { db in
            try db.create(table: "books") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("author", .text).notNull().defaults(to: "")
                t.column("currentPage", .integer).notNull().defaults(to: 0)
                t.column("totalPages", .integer).notNull()
                t.column("status", .text).notNull()
                t.column("emoji", .text).notNull().defaults(to: "📖")
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("quotes", .text).notNull().defaults(to: "[]")
            }
            try db.create(table: "skills") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("category", .text).notNull().defaults(to: "General")
                t.column("level", .integer).notNull().defaults(to: 1)
                t.column("status", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("career-v1") { db in
            try db.create(table: "career_tasks") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("project", .text).notNull().defaults(to: "")
                t.column("priority", .text).notNull()
                t.column("status", .text).notNull()
                t.column("dueDate", .datetime)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "career_projects") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("role", .text).notNull().defaults(to: "")
                t.column("progressPercent", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull()
                t.column("deadline", .datetime)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "interviews") { t in
                t.primaryKey("id", .text)
                t.column("company", .text).notNull()
                t.column("position", .text).notNull()
                t.column("status", .text).notNull()
                t.column("appliedDate", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("career-v2") { db in
            try db.create(table: "achievements") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("date", .datetime).notNull()
                t.column("impact", .text).notNull().defaults(to: "")
            }
            try db.create(table: "network_contacts") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("role", .text).notNull().defaults(to: "")
                t.column("company", .text).notNull().defaults(to: "")
                t.column("note", .text).notNull().defaults(to: "")
                t.column("lastContact", .datetime)
            }
        }

        migrator.registerMigration("rest-v1") { db in
            try db.create(table: "sleep_entries") { t in
                t.primaryKey("id", .text)
                t.column("date", .datetime).notNull()
                t.column("hoursSlept", .double).notNull()
                t.column("recovery", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
                t.column("bedtimeHour", .integer).notNull().defaults(to: 23)
                t.column("bedtimeMinute", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "sleep_schedule") { t in
                t.primaryKey("id", .text)
                t.column("bedtimeHour", .integer).notNull()
                t.column("bedtimeMinute", .integer).notNull()
                t.column("wakeHour", .integer).notNull()
                t.column("wakeMinute", .integer).notNull()
                t.column("goalHours", .double).notNull()
                t.column("remindersEnabled", .boolean).notNull()
            }
            try db.create(table: "detox_days") { t in
                t.primaryKey("dateKey", .text)
            }
            try db.create(table: "work_hours") { t in
                t.primaryKey("dateKey", .text)
                t.column("hours", .double).notNull()
            }
            try db.create(table: "weekend_plans") { t in
                t.primaryKey("weekKey", .text)
                t.column("activities", .text).notNull().defaults(to: "[]")
                t.column("location", .text).notNull().defaults(to: "")
                t.column("withWho", .text).notNull().defaults(to: "")
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("travel-v1") { db in
            try db.create(table: "travel_plans") { t in
                t.primaryKey("id", .text)
                t.column("destination", .text).notNull()
                t.column("country", .text).notNull().defaults(to: "")
                t.column("emoji", .text).notNull().defaults(to: "✈️")
                t.column("type", .text).notNull()
                t.column("status", .text).notNull()
                t.column("startDate", .datetime)
                t.column("endDate", .datetime)
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("budget", .double).notNull().defaults(to: 0)
                t.column("packingList", .text).notNull().defaults(to: "{}")
                t.column("documents", .text).notNull().defaults(to: "{}")
            }
            try db.create(table: "visited_countries") { t in
                t.primaryKey("name", .text)
                t.column("flag", .text).notNull()
                t.column("year", .integer)
            }
            try db.create(table: "wishlist_destinations") { t in
                t.primaryKey("id", .text)
                t.column("destination", .text).notNull()
                t.column("country", .text).notNull()
                t.column("flag", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("mindfulness-v1") { db in
            try db.create(table: "meditation_sessions") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("durationMinutes", .integer).notNull()
                t.column("date", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
                t.column("moodBefore", .integer).notNull().defaults(to: 3)
                t.column("moodAfter", .integer).notNull().defaults(to: 4)
            }
            try db.create(table: "journal_entries") { t in
                t.primaryKey("id", .text)
                t.column("date", .datetime).notNull()
                t.column("text", .text).notNull()
                t.column("sentiment", .double)
            }
            try db.create(table: "moods") { t in
                t.primaryKey("dateKey", .text)
                t.column("score", .integer).notNull()
            }
            try db.create(table: "stress_levels") { t in
                t.primaryKey("dateKey", .text)
                t.column("level", .integer).notNull()
            }
        }

        migrator.registerMigration("home-v1") { db in
            try db.create(table: "home_tasks") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("category", .text).notNull()
                t.column("status", .text).notNull()
                t.column("dueDate", .datetime)
                t.column("isRecurring", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "plants") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull().defaults(to: "🌿")
                t.column("lastWatered", .datetime)
                t.column("intervalDays", .integer).notNull().defaults(to: 3)
            }
            try db.create(table: "shopping_items") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("category", .text).notNull().defaults(to: "General")
                t.column("checked", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("creativity-v1") { db in
            try db.create(table: "creative_projects") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("type", .text).notNull()
                t.column("status", .text).notNull()
                t.column("progressPercent", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("lastWorkedOn", .datetime)
                t.column("collaborators", .text).notNull().defaults(to: "[]")
            }
            try db.create(table: "inspirations") { t in
                t.primaryKey("id", .text)
                t.column("content", .text).notNull()
                t.column("tag", .text).notNull().defaults(to: "Idea")
                t.column("date", .datetime).notNull()
            }
        }

        migrator.registerMigration("hobbies-v1") { db in
            try db.create(table: "hobbies") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull().defaults(to: "🎸")
                t.column("frequency", .text).notNull()
                t.column("targetMinutesPerWeek", .integer).notNull().defaults(to: 60)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("goal", .text).notNull().defaults(to: "")
                t.column("equipment", .text).notNull().defaults(to: "[]")
                t.column("resources", .text).notNull().defaults(to: "[]")
            }
            try db.create(table: "hobby_sessions") { t in
                t.primaryKey("id", .text)
                t.column("hobbyId", .text).notNull().indexed()
                t.column("durationMinutes", .integer).notNull()
                t.column("date", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("profile-v1") { db in
            // Single row (id = "main"); the profile schema grows over time,
            // so it is stored as one JSON blob rather than typed columns.
            try db.create(table: "user_profile") { t in
                t.primaryKey("id", .text)
                t.column("data", .text).notNull()
            }
        }

        migrator.registerMigration("relationships-v1") { db in
            try db.create(table: "contacts") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull().defaults(to: "👤")
                t.column("type", .text).notNull()
                t.column("birthday", .datetime)
                t.column("lastContact", .datetime)
                t.column("note", .text).notNull().defaults(to: "")
                t.column("reminderDays", .integer).notNull().defaults(to: 30)
                t.column("giftIdeas", .text).notNull().defaults(to: "[]")
                t.column("meetingNotes", .text).notNull().defaults(to: "[]")
                t.column("sharedExperiences", .text).notNull().defaults(to: "[]")
                t.column("importantInfo", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("health-v3") { db in
            try db.create(table: "cycle_entries") { t in
                t.primaryKey("id", .text)
                t.column("startDate", .datetime).notNull()
                t.column("endDate", .datetime)
                t.column("flow", .text).notNull().defaults(to: "medium")
                t.column("symptoms", .text).notNull().defaults(to: "[]")
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("health-v4") { db in
            // Day-keyed one-tap logs (1–5), the cheapest correlates for the
            // Stage-6 insight engine. Deliberately not calorie counting.
            try db.create(table: "energy_levels") { t in
                t.primaryKey("dateKey", .text)
                t.column("level", .integer).notNull()
            }
            try db.create(table: "meal_quality") { t in
                t.primaryKey("dateKey", .text)
                t.column("quality", .integer).notNull()
            }
        }

        migrator.registerMigration("mindfulness-v2") { db in
            try db.create(table: "gratitude_entries") { t in
                t.primaryKey("id", .text)
                t.column("date", .datetime).notNull()
                t.column("content", .text).notNull()
            }
            try db.create(table: "affirmations") { t in
                t.primaryKey("id", .text)
                t.column("text", .text).notNull()
                t.column("isCustom", .boolean).notNull().defaults(to: true)
            }
        }

        migrator.registerMigration("readiness-v1") { db in
            try db.create(table: "readiness_log") { t in
                t.primaryKey("dateKey", .text)
                t.column("predicted", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("experiments-v1") { db in
            try db.create(table: "experiments") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
                t.column("startDate", .datetime).notNull()
                t.column("durationDays", .integer).notNull()
                t.column("status", .text).notNull().defaults(to: "running")
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("reviews-v1") { db in
            try db.create(table: "reviews") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("periodKey", .text).notNull()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("selfRatings", .text).notNull().defaults(to: "{}")
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("nudges-v1") { db in
            try db.create(table: "nudge_log") { t in
                t.primaryKey("id", .text)
                t.column("firedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("goals-v2") { db in
            try db.alter(table: "goals") { t in
                t.add(column: "why", .text).notNull().defaults(to: "")
            }
            try db.alter(table: "habits") { t in
                t.add(column: "identity", .text).notNull().defaults(to: "")
                t.add(column: "reminderWeekdays", .text).notNull().defaults(to: "[]")
            }
            try db.create(table: "anti_goals") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("hobbies-v2") { db in
            try db.alter(table: "hobbies") { t in
                t.add(column: "costTotal", .double).notNull().defaults(to: 0)
            }
            try db.alter(table: "hobby_sessions") { t in
                t.add(column: "rating", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "hobby_milestones") { t in
                t.primaryKey("id", .text)
                t.column("hobbyId", .text).notNull()
                t.column("title", .text).notNull()
                t.column("done", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("creativity-v2") { db in
            try db.create(table: "portfolio_items") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("type", .text).notNull()
                t.column("url", .text).notNull().defaults(to: "")
                t.column("date", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "project_sessions") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("minutes", .integer).notNull()
            }
        }

        migrator.registerMigration("travel-v2") { db in
            try db.alter(table: "travel_plans") { t in
                t.add(column: "spent", .double).notNull().defaults(to: 0)
            }
            try db.create(table: "trip_journal") { t in
                t.primaryKey("id", .text)
                t.column("tripId", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("text", .text).notNull()
            }
        }

        migrator.registerMigration("travel-v3") { db in
            try db.create(table: "trip_photos") { t in
                t.primaryKey("id", .text)
                t.column("planId", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("caption", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("relationships-v2") { db in
            try db.create(table: "custom_dates") { t in
                t.primaryKey("id", .text)
                t.column("contactId", .text).notNull()
                t.column("label", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("recursYearly", .boolean).notNull().defaults(to: true)
            }
            try db.create(table: "message_templates") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
            }
        }

        migrator.registerMigration("career-v3") { db in
            try db.create(table: "career_skills") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("category", .text).notNull().defaults(to: "General")
                t.column("level", .integer).notNull().defaults(to: 3)
            }
            try db.create(table: "salary_entries") { t in
                t.primaryKey("id", .text)
                t.column("amount", .double).notNull()
                t.column("role", .text).notNull().defaults(to: "")
                t.column("company", .text).notNull().defaults(to: "")
                t.column("date", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "career_goals") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("status", .text).notNull()
                t.column("progressPercent", .integer).notNull().defaults(to: 0)
                t.column("targetDate", .datetime)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "one_on_ones") { t in
                t.primaryKey("id", .text)
                t.column("person", .text).notNull()
                t.column("role", .text).notNull().defaults(to: "")
                t.column("date", .datetime).notNull()
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("talkingPoints", .text).notNull().defaults(to: "[]")
            }
        }

        migrator.registerMigration("home-v2") { db in
            try db.alter(table: "home_tasks") { t in
                t.add(column: "recurrenceDays", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "appliances") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("brand", .text).notNull().defaults(to: "")
                t.column("purchaseDate", .datetime)
                t.column("warrantyUntil", .datetime)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "utility_readings") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("value", .double).notNull()
                t.column("cost", .double).notNull().defaults(to: 0)
                t.column("date", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "renovation_projects") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("status", .text).notNull()
                t.column("budget", .double).notNull().defaults(to: 0)
                t.column("spent", .double).notNull().defaults(to: 0)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "inventory_items") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("quantity", .integer).notNull().defaults(to: 1)
                t.column("location", .text).notNull().defaults(to: "")
                t.column("lentTo", .text).notNull().defaults(to: "")
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("rest-v2") { db in
            try db.create(table: "naps") { t in
                t.primaryKey("id", .text)
                t.column("date", .datetime).notNull()
                t.column("minutes", .integer).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "recovery_activities") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull().defaults(to: "🌿")
                t.column("rating", .integer).notNull().defaults(to: 3)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "vacation_days") { t in
                t.primaryKey("dateKey", .text)
            }
        }

        migrator.registerMigration("learning-v2") { db in
            try db.create(table: "courses") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("provider", .text).notNull().defaults(to: "")
                t.column("progressPercent", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "languages") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("level", .text).notNull().defaults(to: "A1")
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "learning_queue") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("url", .text).notNull().defaults(to: "")
                t.column("done", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "flashcards") { t in
                t.primaryKey("id", .text)
                t.column("deck", .text).notNull().defaults(to: "General")
                t.column("front", .text).notNull()
                t.column("back", .text).notNull()
                t.column("easiness", .double).notNull().defaults(to: 2.5)
                t.column("intervalDays", .integer).notNull().defaults(to: 0)
                t.column("repetitions", .integer).notNull().defaults(to: 0)
                t.column("dueDate", .datetime).notNull()
                t.column("lastReviewed", .datetime)
            }
        }

        migrator.registerMigration("finance-v3") { db in
            try db.create(table: "debts") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("lender", .text).notNull().defaults(to: "")
                t.column("totalAmount", .double).notNull()
                t.column("remaining", .double).notNull()
                t.column("monthlyPayment", .double).notNull().defaults(to: 0)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "investments") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("value", .double).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "wishlist") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("amount", .double).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("ritual-v1") { db in
            try db.create(table: "daily_ritual") { t in
                t.primaryKey("dateKey", .text)
                t.column("intention", .text).notNull().defaults(to: "")
                t.column("plannedFocusIds", .text).notNull().defaults(to: "[]")
                t.column("reflection", .text).notNull().defaults(to: "")
                t.column("morningCompletedAt", .datetime)
                t.column("eveningCompletedAt", .datetime)
            }
        }

        return migrator
    }
}
