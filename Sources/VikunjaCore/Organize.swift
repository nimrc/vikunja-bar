import Foundation

public enum Bucket: Int, CaseIterable, Sendable, Comparable {
    case overdue, today, week, later, undated

    public var title: String {
        switch self {
        case .overdue: "已逾期"
        case .today: "今天"
        case .week: "未来 7 天"
        case .later: "以后"
        case .undated: "无截止日期"
        }
    }

    public static func < (a: Bucket, b: Bucket) -> Bool { a.rawValue < b.rawValue }
}

public enum Organize {
    /// Open tasks grouped by due date relative to `now`, each group sorted by due date then priority.
    public static func overview(_ tasks: [TaskItem], now: Date = .now,
                                calendar: Calendar = .current) -> [(Bucket, [TaskItem])] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let weekEnd = calendar.date(byAdding: .day, value: 8, to: startOfToday)!
        var groups = [Bucket: [TaskItem]]()
        for t in tasks where !t.done {
            let b: Bucket = switch t.dueDate {
            case nil: .undated
            case let d? where d < now: .overdue
            case let d? where d < startOfTomorrow: .today
            case let d? where d < weekEnd: .week
            default: .later
            }
            groups[b, default: []].append(t)
        }
        return Bucket.allCases.compactMap { b in
            guard let items = groups[b] else { return nil }
            return (b, items.sorted { l, r in
                if l.dueDate != r.dueDate { return (l.dueDate ?? .distantFuture) < (r.dueDate ?? .distantFuture) }
                return l.priority > r.priority
            })
        }
    }

    /// Number shown on the menu bar icon: overdue plus due today.
    public static func urgentCount(_ tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> Int {
        overview(tasks, now: now, calendar: calendar)
            .filter { $0.0 == .overdue || $0.0 == .today }
            .reduce(0) { $0 + $1.1.count }
    }

    /// Unarchived projects in tree order (children right after their parent), with their depth.
    /// Saved filters are left out; a child whose parent is missing is shown at the top level.
    public static func tree(_ projects: [Project]) -> [(project: Project, depth: Int)] {
        let visible = projects.filter { !$0.isArchived && !$0.isSavedFilter }
        let ids = Set(visible.map(\.id))
        let children = Dictionary(grouping: visible) { ids.contains($0.parentProjectID) ? $0.parentProjectID : 0 }
        var out = [(project: Project, depth: Int)]()
        func walk(_ parent: Int, _ depth: Int) {
            for p in (children[parent] ?? []).sorted(by: { ($0.position, $0.id) < ($1.position, $1.id) }) {
                out.append((p, depth))
                walk(p.id, depth + 1)
            }
        }
        walk(0, 0)
        return out
    }
}
