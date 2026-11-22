import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo = "To do"
    case inProgress = "In progress"
    case done = "Done"

    var id: String { rawValue }
}

struct TaskDetails: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var due: String?
    var dueTime: String?
    var status: TaskStatus = .todo
    var progress = 0
    var notes = ""
    var project = ""
    var keyDate: String?
    var keyTime: String?
    var createdAt = Date()

    mutating func setStatus(_ value: TaskStatus) {
        status = value
        switch value {
        case .todo: progress = 0
        case .inProgress: progress = min(99, max(1, progress))
        case .done: progress = 100
        }
    }

    mutating func setProgress(_ value: Int) {
        progress = min(100, max(0, value))
        switch progress {
        case 0: status = .todo
        case 100: status = .done
        default: status = .inProgress
        }
    }

    mutating func validate() throws {
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        project = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TaskError.invalidTitle }
        guard [due, keyDate].compactMap({ $0 }).allSatisfy({ Day.date($0) != nil }) else {
            throw TaskError.invalidDate
        }
        guard (dueTime == nil || (due != nil && dueTime.flatMap { Day.timeDate($0) } != nil)),
              (keyTime == nil || (keyDate != nil && keyTime.flatMap { Day.timeDate($0) } != nil)) else {
            throw TaskError.invalidTime
        }
        setStatus(status)
    }
}

enum TaskError: LocalizedError {
    case invalidTitle, invalidDate, invalidTime, unsupportedBackup

    var errorDescription: String? {
        switch self {
        case .invalidTitle: "Enter a task title."
        case .invalidDate: "A task contains an invalid calendar date."
        case .invalidTime: "A task contains an invalid time or a time without a date."
        case .unsupportedBackup: "This backup version is newer than this app supports."
        }
    }
}

enum Day {
    // Use local Gregorian calendar days, stored without a time or time zone.
    static var calendar: Calendar { Calendar(identifier: .gregorian) }

    static func key(_ date: Date, calendar: Calendar = Day.calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1, parts.month ?? 1, parts.day ?? 1)
    }

    static func date(_ key: String, calendar: Calendar = Day.calendar) -> Date? {
        guard key.utf8.count == 10 else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              Day.key(date, calendar: calendar) == key else { return nil }
        return date
    }

    // Store times as local clock values. A fixed UTC anchor keeps formatting and editing
    // independent of whether the selected calendar day crosses a daylight-saving change.
    static let clockTimeZone = TimeZone(secondsFromGMT: 0)!
    static var clockCalendar: Calendar {
        var clock = Calendar(identifier: .gregorian)
        clock.timeZone = clockTimeZone
        return clock
    }

    static func timeKey(_ date: Date, calendar: Calendar = Day.clockCalendar) -> String {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0)
    }

    static func timeDate(_ key: String, calendar: Calendar = Day.clockCalendar) -> Date? {
        guard key.utf8.count == 5 else { return nil }
        let parts = key.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]),
              let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 15,
                                                             hour: parts[0], minute: parts[1])),
              timeKey(date, calendar: calendar) == key else { return nil }
        return date
    }

    static func timeLabel(_ key: String) -> String? {
        guard let date = timeDate(key) else { return nil }
        var format = Date.FormatStyle().hour().minute()
        format.timeZone = clockTimeZone
        return date.formatted(format)
    }

    static func sortKey(day: String?, time: String?) -> String {
        (day ?? "9999-99-99") + " " + (time ?? "")
    }

    static func isPast(day: String, time: String?, now: Date, calendar: Calendar = Day.calendar) -> Bool {
        let today = key(now, calendar: calendar)
        if day != today { return day < today }
        guard let time else { return false }
        return time < timeKey(now, calendar: calendar)
    }

}

enum TaskView: String, CaseIterable, Identifiable {
    case overview, today, upcoming, milestones, completed, allTasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .today: "Today & overdue"
        case .upcoming: "Upcoming 7 days"
        case .milestones: "Exams & milestones"
        case .completed: "Completed"
        case .allTasks: "All tasks"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .milestones: "flag"
        case .completed: "checkmark.circle"
        case .allTasks: "tray.full"
        }
    }

    var emptyTitle: String {
        switch self {
        case .overview: "Nothing Scheduled This Week"
        case .today: "You’re Caught Up"
        case .upcoming: "Nothing Due Soon"
        case .milestones: "No Upcoming Milestones"
        case .completed: "No Completed Tasks"
        case .allTasks: "No Tasks Yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .overview: "Tasks with a due date or key date this week appear here."
        case .today: "You’re caught up on tasks due today or earlier."
        case .upcoming: "Nothing is due in the next seven days."
        case .milestones: "Set a key date on a task to see it here."
        case .completed: "Tasks you finish will appear here."
        case .allTasks: "Add a task to get started."
        }
    }

    func visibleTasks(_ tasks: [TaskDetails], now: Date, calendar: Calendar = Day.calendar) -> [TaskDetails] {
        let window = TaskDateWindow(now: now, calendar: calendar)
        return tasks.filter { window.includes($0, in: self) }.sorted {
            func sortDate(_ task: TaskDetails) -> String {
                if self == .milestones || (self == .overview && window.week.usesKeyDate(for: task)) {
                    return Day.sortKey(day: task.keyDate, time: task.keyTime)
                }
                return Day.sortKey(day: task.due, time: task.dueTime)
            }
            let firstDate = sortDate($0)
            let secondDate = sortDate($1)
            if firstDate != secondDate { return firstDate < secondDate }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

private struct TaskDateWindow {
    let today: String
    let upcomingEnd: String
    let week: SnapshotWeek

    init(now: Date, calendar: Calendar) {
        today = Day.key(now, calendar: calendar)
        upcomingEnd = calendar.date(byAdding: .day, value: 7, to: now)
            .map { Day.key($0, calendar: calendar) } ?? today
        week = SnapshotWeek(now: now, calendar: calendar)
    }

    func includes(_ task: TaskDetails, in view: TaskView) -> Bool {
        switch view {
        case .overview:
            week.contains(day: task.due, time: task.dueTime) ||
                week.contains(day: task.keyDate, time: task.keyTime)
        case .allTasks: true
        case .today: task.status != .done && task.due.map { $0 <= today } == true
        case .upcoming: task.status != .done && task.due.map { $0 > today && $0 <= upcomingEnd } == true
        case .milestones: task.keyDate.map { $0 >= today } == true
        case .completed: task.status == .done
        }
    }
}

// Owned by the workspace on the main thread. Replaced after a successful save.
final class WorkspaceIndex {
    let tasks: [TaskDetails]
    let projects: [String]
    private var window: TaskDateWindow?
    private var sidebarCounts: [TaskView: Int] = [:]
    private var lastView: TaskView?
    private var lastRows: [TaskDetails] = []

    struct Query: Equatable {
        let project: String
        let status: TaskStatus?
        let term: String
        let order: [KeyPathComparator<TaskDetails>]
    }

    struct Result {
        let rows: [TaskDetails]
        let sectionCount: Int
        let summary: [OverviewSection: Int]
    }

    private var lastQuery: Query?
    private var lastResult: Result?

    func result(for view: TaskView, now: Date, query: Query) -> Result {
        let section = rows(view, now: now)
        if lastQuery == query, let lastResult { return lastResult }
        var visible = section
        if !query.project.isEmpty || query.status != nil || !query.term.isEmpty {
            visible = section.filter { task in
                (query.project.isEmpty || task.project == query.project) &&
                (query.status == nil || task.status == query.status) &&
                (query.term.isEmpty || task.title.localizedStandardContains(query.term) ||
                    task.notes.localizedStandardContains(query.term) || task.project.localizedStandardContains(query.term))
            }
        }
        if !query.order.isEmpty { visible.sort(using: query.order) }
        let summary = view == .overview ? OverviewSection.group(visible, now: now).mapValues(\.count) : [:]
        let result = Result(rows: visible, sectionCount: section.count, summary: summary)
        lastQuery = query
        lastResult = result
        return result
    }

    init(_ tasks: [TaskDetails]) {
        self.tasks = tasks
        projects = Set(tasks.lazy.map(\.project).filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func refresh(now: Date, calendar: Calendar) {
        let current = TaskDateWindow(now: now, calendar: calendar)
        guard current.today != window?.today || current.week.start != window?.week.start ||
                current.upcomingEnd != window?.upcomingEnd else { return }
        window = current
        sidebarCounts = [.allTasks: tasks.count]
        for task in tasks {
            for view: TaskView in [.today, .upcoming, .completed, .milestones] where current.includes(task, in: view) {
                sidebarCounts[view, default: 0] += 1
            }
        }
        lastView = nil
    }

    func rows(_ view: TaskView, now: Date, calendar: Calendar = Day.calendar) -> [TaskDetails] {
        refresh(now: now, calendar: calendar)
        if view != lastView {
            lastResult = nil
            lastRows = view.visibleTasks(tasks, now: now, calendar: calendar)
            lastView = view
        }
        return lastRows
    }

    func counts(now: Date, calendar: Calendar = Day.calendar) -> [TaskView: Int] {
        refresh(now: now, calendar: calendar)
        return sidebarCounts
    }
}

struct SnapshotWeek {
    let start: Date
    let end: Date
    private let startKey: String
    private let endKey: String

    init(now: Date, calendar: Calendar = Day.calendar) {
        let daysSinceSunday = calendar.component(.weekday, from: now) - 1
        let today = calendar.startOfDay(for: now)
        let sunday = calendar.date(byAdding: .day, value: -daysSinceSunday, to: today) ?? today
        let boundary = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: sunday) ?? sunday
        start = now < boundary ? calendar.date(byAdding: .day, value: -7, to: boundary) ?? boundary : boundary
        end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        startKey = Day.sortKey(day: Day.key(start, calendar: calendar), time: "07:00")
        endKey = Day.sortKey(day: Day.key(end, calendar: calendar), time: "07:00")
    }

    func contains(day: String?, time: String?) -> Bool {
        guard let day else { return false }
        // An all-day item belongs to the week that begins on its Sunday.
        let key = Day.sortKey(day: day, time: time ?? "07:00")
        return key >= startKey && key < endKey
    }

    func usesKeyDate(for task: TaskDetails) -> Bool {
        !contains(day: task.due, time: task.dueTime) && contains(day: task.keyDate, time: task.keyTime)
    }
}

enum OverviewSection: String, CaseIterable, Identifiable {
    case overdue = "Overdue"
    case today = "Today"
    case upcoming = "Upcoming"
    case later = "Later"
    case unscheduled = "No due date"
    case completed = "Completed"

    var id: Self { self }

    static func group(_ tasks: [TaskDetails], now: Date, calendar: Calendar = Day.calendar) -> [Self: [TaskDetails]] {
        let today = Day.key(now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: now)
            .map { Day.key($0, calendar: calendar) } ?? today
        let week = SnapshotWeek(now: now, calendar: calendar)
        return Dictionary(grouping: tasks) { task in
            if task.status == .done { return .completed }
            let date = week.usesKeyDate(for: task) ? task.keyDate : task.due
            guard let due = date else { return .unscheduled }
            if due < today { return .overdue }
            if due == today { return .today }
            return due <= weekEnd ? .upcoming : .later
        }
    }
}

struct TaskBackup: Codable {
    var version = 1
    var tasks: [TaskDetails]

    func newTasks(excluding existingIDs: Set<UUID>) throws -> [TaskDetails] {
        guard version == 1 || version == 2 else { throw TaskError.unsupportedBackup }
        var seen = existingIDs
        var result: [TaskDetails] = []
        for var task in tasks where seen.insert(task.id).inserted {
            try task.validate()
            result.append(task)
        }
        return result
    }
}

extension TaskDetails {
    var dueDateSort: String { Day.sortKey(day: due, time: dueTime) }
    var keyDateSort: String { Day.sortKey(day: keyDate, time: keyTime) }

    var statusSort: Int {
        switch status {
        case .todo: 0
        case .inProgress: 1
        case .done: 2
        }
    }
}

enum TaskSortField: String, CaseIterable {
    case title = "Title"
    case due = "Due date"
    case key = "Key date"
    case status = "Status"
    case progress = "Progress"
    case project = "Project"
    case created = "Date added"

    func comparator(order: SortOrder = .forward) -> KeyPathComparator<TaskDetails> {
        switch self {
        case .title: KeyPathComparator(\.title, order: order)
        case .due: KeyPathComparator(\.dueDateSort, order: order)
        case .key: KeyPathComparator(\.keyDateSort, order: order)
        case .status: KeyPathComparator(\.statusSort, order: order)
        case .progress: KeyPathComparator(\.progress, order: order)
        case .project: KeyPathComparator(\.project, order: order)
        case .created: KeyPathComparator(\.createdAt, order: order)
        }
    }
}

struct TaskSortRule: Equatable {
    var field: TaskSortField
    var order: SortOrder = .forward

    var comparator: KeyPathComparator<TaskDetails> { field.comparator(order: order) }

    static func applyingHeaderOrder(_ order: [KeyPathComparator<TaskDetails>], to rules: [Self]) -> [Self] {
        guard let primary = order.first else { return [] }
        guard let field = TaskSortField.allCases.first(where: { $0.comparator().keyPath == primary.keyPath }) else {
            return rules
        }
        return [Self(field: field, order: primary.order)] + rules.filter { $0.field != field }
    }
}
