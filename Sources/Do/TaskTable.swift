import AppKit
import SwiftUI

struct TaskTable: View {
    let tasks: [TaskDetails]
    let view: TaskView
    let now: Date
    let theme: WorkspaceTheme
    @Binding var selection: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<TaskDetails>]
    let open: (TaskDetails) -> Void
    let toggle: (TaskDetails) -> Void
    let delete: (Set<UUID>) -> Void

    var body: some View {
        Table(tasks, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Task", value: \.title, content: taskCell)
                .width(min: 165, ideal: 260)
            TableColumn(view == .milestones ? "Key date" : "Due date",
                        value: view == .milestones ? \.keyDateSort : \.dueDateSort,
                        content: dateLabel)
                .width(min: 94, ideal: 112)
            TableColumn("Status", value: \.statusSort, content: statusLabel)
                .width(min: 88, ideal: 100)
            TableColumn("Progress", value: \.progress, content: progressLabel)
                .width(min: 80, ideal: 96)
            TableColumn("Course / project", value: \.project, content: projectLabel)
                .width(min: 106, ideal: 136)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(theme.paper)
        .taskRowActions(tasks: tasks, selection: selection, open: open, toggle: toggle, delete: delete)
    }

    private func taskCell(_ task: TaskDetails) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 24)
                .overlay {
                    TaskRangeHandle { start, end in
                        guard tasks.indices.contains(start), tasks.indices.contains(end) else { return }
                        selection = Set(tasks[min(start, end)...max(start, end)].map(\.id))
                    }
                }
                .help("Drag to select a range of tasks")
                .accessibilityHidden(true)
            TaskCompletionButton(task: task, compact: true) { toggle(task) }
            Text(task.title)
                .workspaceType(.task)
                .foregroundStyle(task.status == .done ? theme.muted : .primary)
                .lineLimit(1)
                .help(task.title)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
    }

    private func dateLabel(_ task: TaskDetails) -> some View {
        let date = TaskDateDisplay(task: task, view: view, now: now)
        return VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(date.label).monospacedDigit().lineLimit(1)
            } icon: {
                if date.overdue { Image(systemName: "exclamationmark.circle").accessibilityHidden(true) }
            }
            .labelStyle(CompactLabelStyle())
            if let clock = date.clock {
                Text(clock).workspaceType(.metadata).monospacedDigit().lineLimit(1)
            }
        }
        .workspaceType(.metadata)
        .foregroundStyle(date.overdue ? .primary : theme.muted)
        .help(date.fullLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.fullLabel)
    }

    private func statusLabel(_ task: TaskDetails) -> some View {
        Label(task.status.rawValue, systemImage: statusSymbol(task.status))
            .labelStyle(CompactLabelStyle())
            .workspaceType(.metadata)
            .foregroundStyle(task.status == .todo ? theme.muted : .primary)
            .lineLimit(1)
    }

    private func statusSymbol(_ status: TaskStatus) -> String {
        switch status {
        case .todo: "circle.dotted"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark"
        }
    }

    private func progressLabel(_ task: TaskDetails) -> some View {
        let progress = min(100, max(0, task.progress))
        return HStack(spacing: Space.xs) {
            GeometryReader { track in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.ink.opacity(theme.highContrast ? 0.22 : 0.10))
                    if progress > 0 {
                        Capsule().fill(theme.action)
                            .frame(width: track.size.width * CGFloat(progress) / 100)
                    }
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)

            Text("\(progress)%")
                .workspaceType(.metadata).monospacedDigit()
                .foregroundStyle(theme.muted)
                .fixedSize()
                .frame(minWidth: 32, alignment: .trailing)
                .layoutPriority(1)
                .accessibilityLabel("Progress \(progress) percent")
        }
    }

    private func projectLabel(_ task: TaskDetails) -> some View {
        Text(task.project.isEmpty ? "—" : task.project)
            .workspaceType(.metadata)
            .lineLimit(1)
            .foregroundStyle(theme.muted)
            .help(task.project)
    }
}

private struct TaskRangeHandle: NSViewRepresentable {
    let selectRange: (Int, Int) -> Void

    func makeNSView(context: Context) -> Handle { Handle() }

    func updateNSView(_ view: Handle, context: Context) {
        view.selectRange = selectRange
    }

    final class Handle: NSView {
        var selectRange: ((Int, Int) -> Void)?
        private var startRow = -1

        private var table: NSTableView? {
            var ancestor = superview
            while let view = ancestor {
                if let table = view as? NSTableView { return table }
                ancestor = view.superview
            }
            return nil
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            guard let table else { return }
            window?.makeFirstResponder(table)
            startRow = table.row(at: table.convert(event.locationInWindow, from: nil))
            if startRow >= 0 { selectRange?(startRow, startRow) }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let table, startRow >= 0, table.numberOfRows > 0 else { return }
            _ = table.autoscroll(with: event)
            var location = table.convert(event.locationInWindow, from: nil)
            let first = table.rect(ofRow: 0)
            let last = table.rect(ofRow: table.numberOfRows - 1)
            location.y = min(max(location.y, first.midY), last.midY)
            let endRow = table.row(at: location)
            if endRow >= 0 { selectRange?(startRow, endRow) }
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

struct TaskDateDisplay {
    let overdue: Bool
    let label: String
    let clock: String?
    let fullLabel: String

    init(task: TaskDetails, view: TaskView, now: Date) {
        let usesKeyDate = view == .milestones
        let key = usesKeyDate ? task.keyDate : task.due
        let time = usesKeyDate ? task.keyTime : task.dueTime
        let date = key.flatMap { Day.date($0) }
        let today = Day.key(now)
        let tomorrow = Day.calendar.date(byAdding: .day, value: 1, to: now).map { Day.key($0) }
        overdue = !usesKeyDate && task.status != .done &&
            (key.map { Day.isPast(day: $0, time: time, now: now) } ?? false)
        clock = time.flatMap { Day.timeLabel($0) }
        if key == today {
            label = "Today"
        } else if let key, key == tomorrow {
            label = "Tomorrow"
        } else if let date {
            let format = Date.FormatStyle().month(.abbreviated).day()
            label = date.formatted(Day.calendar.isDate(date, equalTo: now, toGranularity: .year) ? format : format.year())
        } else {
            label = "—"
        }
        fullLabel = [date?.formatted(date: .long, time: .omitted) ?? "No date", clock, overdue ? "overdue" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

extension View {
    func taskRowActions(tasks: [TaskDetails], selection: Set<UUID>,
                        open: @escaping (TaskDetails) -> Void, toggle: @escaping (TaskDetails) -> Void,
                        delete: @escaping (Set<UUID>) -> Void) -> some View {
        func task(for ids: Set<UUID>) -> TaskDetails? {
            guard ids.count == 1, let id = ids.first else { return nil }
            return tasks.first { $0.id == id }
        }

        return contextMenu(forSelectionType: UUID.self) { ids in
            if let task = task(for: ids) {
                Button("Edit Task…") { open(task) }
                Button(task.status == .done ? "Reopen Task" : "Mark as Done") { toggle(task) }
                Divider()
                Button("Copy Task Title") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(task.title, forType: .string)
                }
                Divider()
            }
            if !ids.isEmpty {
                Button(ids.count == 1 ? "Delete Task…" : "Delete \(ids.count) Tasks…", role: .destructive) {
                    delete(ids)
                }
            }
        } primaryAction: { ids in
            if let task = task(for: ids) { open(task) }
        }
        .onDeleteCommand {
            if !selection.isEmpty { delete(selection) }
        }
        .onKeyPress(.return) {
            guard let task = task(for: selection) else { return .ignored }
            open(task)
            return .handled
        }
    }
}

