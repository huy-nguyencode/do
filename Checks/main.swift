import Foundation

enum CheckFailure: Error {
    case failed(String)
}

func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
    guard try condition() else { throw CheckFailure.failed(label) }
}

func checkViews() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let justBeforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31,
                                                               hour: 23, minute: 59))!
    let midnight = justBeforeMidnight.addingTimeInterval(60)
    let tasks = [
        TaskDetails(title: "Today", due: "2026-10-31"),
        TaskDetails(title: "Day eight", due: "2026-11-08"),
        TaskDetails(title: "Tomorrow", due: "2026-11-01", keyDate: "2026-11-05"),
        TaskDetails(title: "Day seven", due: "2026-11-07"),
        TaskDetails(title: "Late", due: "2026-10-30"),
        TaskDetails(title: "Done", due: "2026-10-31", status: .done, progress: 100, keyDate: "2026-11-01"),
        TaskDetails(title: "Undated")
    ]
    func titles(_ view: TaskView, at now: Date) -> [String] {
        view.visibleTasks(tasks, now: now, calendar: calendar).map(\.title)
    }
    try check(titles(.today, at: justBeforeMidnight) == ["Late", "Today"], "Due before midnight")
    try check(titles(.today, at: midnight) == ["Late", "Today", "Tomorrow"], "Due after midnight")
    try check(titles(.upcoming, at: justBeforeMidnight) == ["Tomorrow", "Day seven"], "Week across DST")
    try check(titles(.upcoming, at: midnight) == ["Day seven", "Day eight"], "Week after midnight")
    try check(titles(.milestones, at: midnight) == ["Done", "Tomorrow"], "Separate key dates")
    try check(titles(.allTasks, at: midnight).count == 7, "All Tasks includes every task")
    try check(titles(.completed, at: midnight) == ["Done"], "Completed view shows finished tasks")
    let grouped = OverviewSection.group(tasks, now: justBeforeMidnight, calendar: calendar)
    try check(grouped[.today]?.map(\.title) == ["Today"], "Today summary excludes overdue and completed tasks")
    try check(grouped[.overdue]?.map(\.title) == ["Late"], "Overdue tasks have their own group")
    try check(grouped[.later]?.map(\.title) == ["Day eight"], "Tasks outside the next week remain visible")
    try check(grouped[.unscheduled]?.map(\.title) == ["Undated"], "Undated tasks remain visible")
    try check(grouped.values.reduce(0) { $0 + $1.count } == tasks.count, "Each task appears in one overview group")
    try check(Day.date("2026-02-30", calendar: calendar) == nil, "Invalid calendar date")
}

func checkBackup() throws {
    let existing = TaskDetails(title: "Existing")
    var imported = TaskDetails(title: " Review ", project: "Biology")
    imported.setProgress(42)
    let data = try TaskStore.encode([existing, imported, imported])
    let backup = try JSONDecoder().decode(TaskBackup.self, from: data)
    let result = try backup.newTasks(excluding: [existing.id])
    try check(result.map(\.title) == ["Review"], "Import skips matching IDs and trims titles")
    try check(result.first?.progress == 42 && result.first?.status == .inProgress, "Progress round trip")
    do {
        _ = try TaskBackup(version: 3, tasks: []).newTasks(excluding: [])
        throw CheckFailure.failed("Unsupported version accepted")
    } catch TaskError.unsupportedBackup {}
    do {
        _ = try TaskBackup(tasks: [TaskDetails(title: "Valid"), TaskDetails()]).newTasks(excluding: [])
        throw CheckFailure.failed("Invalid title accepted")
    } catch TaskError.invalidTitle {}
}

func checkStorage() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Tasks.json")
    let store = TaskStore(url: url)
    try check(try store.load().isEmpty, "Missing task file")
    var task = TaskDetails(title: "Read chapter", due: "2026-11-21", notes: "Bring notes",
                           project: "Biology", keyDate: "2026-11-24")
    task.setStatus(.done)
    try store.save([task])
    try check(try TaskStore(url: url).load() == [task], "Saved task survives reopen")
    try store.save([])
    try check(try TaskStore(url: url).load().isEmpty, "Deleted task stays deleted")
    try Data("corrupt".utf8).write(to: url)
    do {
        _ = try store.load()
        throw CheckFailure.failed("Corrupt storage accepted")
    } catch is DecodingError {}
}

func checkScheduledTimes() throws {
    let legacy = TaskDetails(title: "All-day task", due: "2026-11-22")
    let morning = TaskDetails(title: "Morning", due: "2026-11-22", dueTime: "09:05")
    let evening = TaskDetails(title: "Evening", due: "2026-11-22", dueTime: "18:30",
                              keyDate: "2026-11-25", keyTime: "13:15")
    let timedBackup = try JSONDecoder().decode(TaskBackup.self, from: TaskStore.encode([evening, morning]))
    try check(timedBackup.version == 2, "Timed backups require the new file version")
    try check(try timedBackup.newTasks(excluding: []) == [evening, morning], "Both clock times survive export")
    let oldBackup = try JSONDecoder().decode(TaskBackup.self, from: TaskStore.encode([legacy]))
    try check(oldBackup.version == 1 && oldBackup.tasks.first?.dueTime == nil, "Legacy all-day task remains all day")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 10))!
    let sorted = TaskView.today.visibleTasks([evening, morning, legacy], now: now, calendar: calendar)
    try check(sorted.map(\.title) == ["All-day task", "Morning", "Evening"], "Same-day tasks sort by clock time")
    try check(Day.isPast(day: "2026-11-22", time: "09:05", now: now, calendar: calendar), "Past time due today")
    try check(!Day.isPast(day: "2026-11-22", time: "18:30", now: now, calendar: calendar), "Future time due today")
    try check(!Day.isPast(day: "2026-11-22", time: nil, now: now, calendar: calendar), "All-day task is due through today")
    try check(Day.timeDate("02:30").map { Day.timeKey($0) } == "02:30", "Clock time round trip independent of DST")
    try check(Day.timeDate("09:00", calendar: calendar).map { Day.timeKey($0, calendar: calendar) } == "09:00",
              "A local time editor returns the time it displays")
    try check(Day.timeDate("24:00") == nil && Day.timeDate("9:00") == nil, "Invalid or noncanonical clock time")
    var orphan = TaskDetails(title: "Missing day", dueTime: "09:00")
    do {
        try orphan.validate()
        throw CheckFailure.failed("Time without a date accepted")
    } catch TaskError.invalidTime {}
}

func checkWeeklySnapshot() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let boundary = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 7))!
    let before = boundary.addingTimeInterval(-60)
    let early = TaskDetails(title: "Before cutoff", due: "2026-11-01", dueTime: "06:59")
    let next = TaskDetails(title: "At cutoff", due: "2026-11-01", dueTime: "07:00")
    let allDay = TaskDetails(title: "Sunday all-day", due: "2026-11-01")
    let milestone = TaskDetails(title: "Key date only", keyDate: "2026-11-05")
    let unscheduled = TaskDetails(title: "Unscheduled")
    let items = [early, next, allDay, milestone, unscheduled]
    try check(TaskView.overview.visibleTasks(items, now: before, calendar: calendar).map(\.id) == [early.id],
              "Sunday before 7 belongs to the preceding snapshot")
    try check(Set(TaskView.overview.visibleTasks(items, now: boundary, calendar: calendar).map(\.id)) ==
              Set([next.id, allDay.id, milestone.id]), "The new snapshot includes dates from Sunday at 7")
    let week = SnapshotWeek(now: before, calendar: calendar)
    try check(calendar.component(.hour, from: week.start) == 7 && calendar.component(.hour, from: week.end) == 7,
              "Rollover uses 7 a.m. on both sides of daylight saving time")
    try check(!week.contains(day: "2026-11-01", time: "07:00"), "The end of a week is exclusive")
}

try checkViews()
print("Passed date and view checks")
try checkBackup()
print("Passed backup and merge checks")
try checkStorage()
print("Passed local storage checks")

try checkScheduledTimes()
print("Passed date and time scheduling checks")

try checkWeeklySnapshot()
print("Passed weekly snapshot rollover checks")

func checkWorkspaceIndex() throws {
    let calendar = Day.calendar
    let sunday = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: Day.date("2026-11-22")!)!
    let tasks = [
        TaskDetails(title: "Morning", due: "2026-11-22", dueTime: "06:59", project: "Biology"),
        TaskDetails(title: "New week", due: "2026-11-22", dueTime: "07:00", project: "Biology"),
        TaskDetails(title: "Later", due: "2026-11-23", status: .done, progress: 100, keyDate: "2026-11-25")
    ]
    let index = WorkspaceIndex(tasks)
    try check(index.projects == ["Biology"], "Project names are distinct")
    for now in [sunday.addingTimeInterval(-60), sunday, sunday.addingTimeInterval(86400)] {
        let counts = index.counts(now: now)
        for view in TaskView.allCases {
            let expected = view.visibleTasks(tasks, now: now)
            try check(index.rows(view, now: now) == expected, "Cached rows match \(view)")
            if view != .overview {
                try check(counts[view, default: 0] == expected.count, "Sidebar count matches \(view)")
            }
        }
    }
    let query = WorkspaceIndex.Query(project: "Biology", status: .todo, term: "week",
                                    order: [KeyPathComparator(\.title, order: .reverse)])
    let selected = index.result(for: .overview, now: sunday, query: query)
    try check(selected.rows.map(\.title) == ["New week"] && selected.summary[.today] == 1,
              "Filters and weekly summary use the same rows")
    let all = WorkspaceIndex.Query(project: "", status: nil, term: "", order: [KeyPathComparator(\.title)])
    try check(index.result(for: .allTasks, now: sunday, query: all).rows.map(\.title) == ["Later", "Morning", "New week"],
              "Changing view, filters and sorting invalidates cached results")
    try check(index.result(for: .overview, now: sunday.addingTimeInterval(-60), query: query).rows.isEmpty,
              "Weekly rollover invalidates filtered results")

}

func checkFileProtection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TaskStore(url: directory.appendingPathComponent("tasks.json"))
    let task = TaskDetails(title: "Fixture")
    for _ in 0..<2 {
        try store.save([task])
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        try check(attributes[.posixPermissions] as? Int == 0o600, "Atomic save uses owner-only permissions")
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.url.path)
    _ = try store.load()
    let migrated = try FileManager.default.attributesOfItem(atPath: store.url.path)
    try check(migrated[.posixPermissions] as? Int == 0o600, "Existing store uses private permissions on open")
    let imported = try TaskStore.importBackup(at: store.url)
    try check(imported.tasks == [task] && imported.total == 1, "Export can be imported")
    let link = directory.appendingPathComponent("alias.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: store.url)
    for invalid in [link, directory] {
        if (try? TaskStore.importBackup(at: invalid)) != nil { throw CheckFailure.failed("Invalid file type accepted") }
    }
    let handle = try FileHandle(forWritingTo: store.url)
    try handle.truncate(atOffset: 64 * 1024 * 1024 + 1)
    try handle.close()
    do {
        _ = try TaskStore.importBackup(at: store.url)
        throw CheckFailure.failed("Oversize file accepted")
    } catch let error as LocalizedError {
        try check(error.errorDescription?.contains("64 MiB") == true, "Size limit checked before decode")
    }
}
try checkWorkspaceIndex()
try checkFileProtection()
print("Passed workspace cache, file protection, and import boundary checks")

func checkSortPriorities() throws {
    let tasks = [
        TaskDetails(title: "Earlier to do", due: "2026-11-22"),
        TaskDetails(title: "Later done", due: "2026-11-24", status: .done, progress: 100),
        TaskDetails(title: "Earlier done", due: "2026-11-22", status: .done, progress: 100)
    ]
    let index = WorkspaceIndex(tasks)
    let now = Day.date("2026-11-22")!
    let rules = [TaskSortRule(field: .status, order: .reverse), TaskSortRule(field: .due)]
    func titles(_ order: [TaskSortRule]) -> [String] {
        index.result(for: .allTasks, now: now, query: .init(
            project: "", status: nil, term: "", order: order.map(\.comparator)
        )).rows.map(\.title)
    }

    try check(titles(rules) == ["Earlier done", "Later done", "Earlier to do"],
              "Due date breaks ties within each status")
    try check(titles(Array(rules.reversed())) == ["Earlier done", "Earlier to do", "Later done"],
              "Changing rule priority changes the order")
    let promoted = TaskSortRule.applyingHeaderOrder([TaskSortField.due.comparator(order: .reverse)], to: rules)
    try check(promoted == [TaskSortRule(field: .due, order: .reverse), rules[0]],
              "A table header promotes its rule and retains the other rule")
    try check(titles([]).first?.hasPrefix("Earlier") == true, "Clearing rules restores default due-date order")
}

try checkSortPriorities()
print("Passed multi-rule sorting and header priority checks")
