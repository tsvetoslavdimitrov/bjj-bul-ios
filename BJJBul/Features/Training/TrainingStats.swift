import Foundation

struct WeekBucket: Identifiable, Hashable {
    let weekStart: Date
    var sessions: Int
    var minutes: Int
    var rounds: Int

    var id: Date { weekStart }
    var hours: Double { Double(minutes) / 60.0 }
}

enum TrainingStats {
    /// Monday-based weeks in Bulgarian time.
    static var calendar: Calendar {
        var calendar = Calendar.bulgaria
        calendar.firstWeekday = 2
        return calendar
    }

    static func weekStart(_ date: Date) -> Date {
        let cal = calendar
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    /// The last `count` weeks (oldest first), including empty ones.
    static func weeks(_ sessions: [TrainingSession], count: Int = 8, now: Date = Date()) -> [WeekBucket] {
        let cal = calendar
        let current = weekStart(now)
        var buckets: [WeekBucket] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let start = cal.date(byAdding: .weekOfYear, value: -offset, to: current) else { continue }
            buckets.append(WeekBucket(weekStart: start, sessions: 0, minutes: 0, rounds: 0))
        }
        for session in sessions {
            let start = weekStart(session.date)
            if let index = buckets.firstIndex(where: { $0.weekStart == start }) {
                buckets[index].sessions += 1
                buckets[index].minutes += session.durationMinutes
                buckets[index].rounds += session.sparringRounds
            }
        }
        return buckets
    }

    /// Consecutive weeks with at least one session, ending this week (or last week if this week is empty so far).
    static func weekStreak(_ sessions: [TrainingSession], now: Date = Date()) -> Int {
        let cal = calendar
        let trained = Set(sessions.map { weekStart($0.date) })
        var cursor = weekStart(now)
        if !trained.contains(cursor) {
            guard let previous = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }
        var streak = 0
        while trained.contains(cursor) {
            streak += 1
            guard let previous = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
