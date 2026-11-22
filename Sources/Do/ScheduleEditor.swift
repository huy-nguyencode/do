import SwiftUI

private typealias ScheduleState<Value> = SwiftUI.State<Value>

struct TaskScheduleField: View {
    @Binding var task: TaskDetails
    let theme: WorkspaceTheme
    @ScheduleState private var showingCalendar = false

    private func caption(day: String?, time: String?) -> String? {
        guard let date = day.flatMap({ Day.date($0) }) else { return nil }
        let dateStyle = Date.FormatStyle().month(.abbreviated).day()
        let sameYear = Day.calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        return [date.formatted(sameYear ? dateStyle : dateStyle.year()), time.flatMap { Day.timeLabel($0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let due = caption(day: task.due, time: task.dueTime)
        let key = caption(day: task.keyDate, time: task.keyTime)
        Button { showingCalendar = true } label: {
            WorkspacePickerLabel(icon: "calendar", theme: theme, focused: showingCalendar, expanded: showingCalendar) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(due ?? "Add due date or key date")
                        .foregroundStyle(due == nil ? theme.muted : theme.ink)
                    if let key {
                        Text("Key date: \(key)").workspaceType(.metadata).foregroundStyle(theme.muted)
                    }
                }
            }
        }
        .buttonStyle(WorkspaceButtonStyle(theme: theme))
        .accessibilityLabel("Due date and key date")
        .accessibilityValue("Due date: \(due ?? "None"). Key date: \(key ?? "None").")
        .popover(isPresented: $showingCalendar, arrowEdge: .leading) {
            ScheduleEditor(task: $task, theme: theme) { showingCalendar = false }
        }
    }
}

private struct ScheduleDraft {
    var day: Date
    var time: Date
    var includesTime: Bool
    var hasDate: Bool

    init(day: String?, time: String?) {
        self.day = day.flatMap { Day.date($0) } ?? Date()
        self.time = Day.timeDate(time ?? "09:00", calendar: Day.calendar) ?? Date()
        includesTime = time != nil
        hasDate = day != nil
    }

    var dayKey: String? { hasDate ? Day.key(day) : nil }
    var timeKey: String? { hasDate && includesTime ? Day.timeKey(time, calendar: Day.calendar) : nil }
}

private struct ScheduleEditor: View {
    @Binding var task: TaskDetails
    let theme: WorkspaceTheme
    let dismiss: () -> Void

    private enum Tab: String { case due = "Due date", key = "Key date" }
    @ScheduleState private var tab: Tab = .due
    @ScheduleState private var due: ScheduleDraft
    @ScheduleState private var key: ScheduleDraft

    init(task: Binding<TaskDetails>, theme: WorkspaceTheme, dismiss: @escaping () -> Void) {
        _task = task
        self.theme = theme
        self.dismiss = dismiss
        _due = ScheduleState(initialValue: ScheduleDraft(day: task.wrappedValue.due, time: task.wrappedValue.dueTime))
        _key = ScheduleState(initialValue: ScheduleDraft(day: task.wrappedValue.keyDate, time: task.wrappedValue.keyTime))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            WorkspaceHeading(title: "Schedule", color: theme.ink, role: .panel)
            Picker("Schedule field", selection: $tab) {
                Text(Tab.due.rawValue).tag(Tab.due)
                Text(Tab.key.rawValue).tag(Tab.key)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScheduleDateFields(value: tab == .due ? $due : $key, theme: theme)
                .id(tab)
            Divider()
            HStack(spacing: Space.sm) {
                Button("Clear Date") {
                    if tab == .due { due.hasDate = false; due.includesTime = false }
                    else { key.hasDate = false; key.includesTime = false }
                }
                .disabled(tab == .due ? !due.hasDate : !key.hasDate)
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button {
                    var revised = task
                    revised.due = due.dayKey
                    revised.dueTime = due.timeKey
                    revised.keyDate = key.dayKey
                    revised.keyTime = key.timeKey
                    task = revised
                    dismiss()
                } label: {
                    Text("Apply").workspaceType(.button)
                        .foregroundStyle(theme.actionInk)
                        .padding(.horizontal, Space.md)
                        .frame(minHeight: 28)
                }
                .buttonStyle(WorkspaceButtonStyle(theme: theme, primary: true))
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(Space.lg)
        .frame(width: 316)
        .foregroundStyle(theme.ink)
        .background(theme.inspector)
        .tint(theme.action)
    }
}

private struct ScheduleDateFields: View {
    @Binding var value: ScheduleDraft
    let theme: WorkspaceTheme

    private var day: Binding<Date> {
        Binding(get: { value.day }, set: { date in
            value.day = date
            value.hasDate = true
        })
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            DatePicker("Date", selection: day, displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                .environment(\.calendar, Day.calendar)
            Spacer(minLength: 2)
            Button("Today") { day.wrappedValue = Date() }
            Button("Tomorrow") {
                let today = Date()
                day.wrappedValue = Day.calendar.date(byAdding: .day, value: 1, to: today) ?? today
            }
        }
        .controlSize(.small)
        MonthCalendar(selection: day, theme: theme, hasDate: value.hasDate)
        Divider()
        HStack {
            Toggle("Include time", isOn: Binding(get: { value.includesTime }, set: {
                value.includesTime = $0
                if $0 { value.hasDate = true }
            }))
            .toggleStyle(.checkbox)
            Spacer()
            if value.includesTime {
                DatePicker("Time", selection: $value.time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                    .environment(\.calendar, Day.calendar)
            } else {
                Text(value.hasDate ? "All day" : "No date").foregroundStyle(theme.muted)
            }
        }
        .workspaceType(.body)
        .frame(minHeight: 25)
    }
}

private struct MonthCalendar: View {
    @Binding var selection: Date
    let theme: WorkspaceTheme
    let hasDate: Bool

    @Environment(\.locale) private var locale
    @FocusState private var focusedDay: Date?
    @ScheduleState private var displayedMonth: Date

    init(selection: Binding<Date>, theme: WorkspaceTheme, hasDate: Bool) {
        _selection = selection
        self.theme = theme
        self.hasDate = hasDate
        _displayedMonth = ScheduleState(initialValue: selection.wrappedValue)
    }

    private var calendar: Calendar {
        var calendar = Day.calendar
        calendar.locale = locale
        return calendar
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    var body: some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: 4) {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .workspaceType(.button)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                monthButton(-1, icon: "chevron.left", label: "Previous month")
                monthButton(1, icon: "chevron.right", label: "Next month")
            }
            let week = calendar.firstWeekday - 1
            let symbols = calendar.veryShortStandaloneWeekdaySymbols
            let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
            let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<7, id: \.self) { column in
                    Text(symbols[(column + week) % 7])
                        .workspaceType(.metadata)
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                // Reserve six rows so the action buttons stay in place when changing months.
                ForEach(0..<42, id: \.self) { column in
                    let offset = column - leading
                    if offset >= 0 && offset < count,
                       let day = calendar.date(byAdding: .day, value: offset, to: monthStart) {
                        dayButton(day)
                    } else {
                        Color.clear.frame(height: 31).accessibilityHidden(true)
                    }
                }
            }
        }
        .onChange(of: selection) { _, date in displayedMonth = date }
    }

    private func monthButton(_ offset: Int, icon: String, label: String) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: offset, to: monthStart) {
                displayedMonth = next
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 27, height: 27)
        }
        .buttonStyle(WorkspaceButtonStyle(theme: theme))
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = hasDate && calendar.isDate(selection, inSameDayAs: day)
        let isToday = calendar.isDateInToday(day)
        return Button {
            selection = day
        } label: {
            Text(calendar.component(.day, from: day), format: .number)
                .font(.callout.weight(selected || isToday ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(selected ? theme.actionInk : isToday ? theme.action : theme.ink)
                .frame(maxWidth: .infinity, minHeight: 31)
                .background {
                    if isToday && !selected {
                        RoundedRectangle(cornerRadius: Corner.control).strokeBorder(theme.action)
                    }
                }
        }
        .buttonStyle(WorkspaceButtonStyle(theme: theme, primary: selected))
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(isToday ? "Today" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Use the arrow keys to move and Space to select.")
        .focused($focusedDay, equals: day)
        .onKeyPress(.leftArrow) { moveFocus(from: day, by: -1) }
        .onKeyPress(.rightArrow) { moveFocus(from: day, by: 1) }
        .onKeyPress(.upArrow) { moveFocus(from: day, by: -7) }
        .onKeyPress(.downArrow) { moveFocus(from: day, by: 7) }
    }

    private func moveFocus(from day: Date, by offset: Int) -> KeyPress.Result {
        guard let next = calendar.date(byAdding: .day, value: offset, to: day) else { return .ignored }
        displayedMonth = next
        Task { @MainActor in
            await Task.yield()
            focusedDay = next
        }
        return .handled
    }
}

