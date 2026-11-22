import SwiftUI

private typealias ViewState<Value> = SwiftUI.State<Value>

struct WorkspaceView: View {
    private let store: TaskStore
    @Binding private var appearance: AppAppearance
    @ViewState private var showingSettings = false
    @Binding private var index: WorkspaceIndex
    private var tasks: [TaskDetails] { index.tasks }
    @ViewState private var view: TaskView = .overview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("headingTypography") private var headingTypography: HeadingTypography = .serif
    @AppStorage("workspaceTextSize") private var textSize: WorkspaceTextSize = .standard
    @ViewState private var statusFilter: TaskStatus?
    @ViewState private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var searchFocused: Bool
    @ViewState private var selection: Set<UUID> = []
    @ViewState private var rulesByView: [TaskView: [TaskSortRule]] = [:]

    private var sortRules: Binding<[TaskSortRule]> {
        let destination = view
        return Binding(get: { rulesByView[destination, default: []] }, set: { rulesByView[destination] = $0 })
    }

    private var sortOrder: Binding<[KeyPathComparator<TaskDetails>]> {
        let rules = sortRules
        return Binding(get: { rules.wrappedValue.map(\.comparator) }, set: {
            rules.wrappedValue = TaskSortRule.applyingHeaderOrder($0, to: rules.wrappedValue)
        })
    }
    @ViewState private var dropTargeted = false
    @ViewState private var search = ""
    @ViewState private var project = ""
    @ViewState private var editor: EditorSession?
    @ViewState private var pendingEditor: EditorAction?
    @ViewState private var showDiscard = false
    @ViewState private var showDelete = false
    @ViewState private var pendingDeletion: Set<UUID> = []

    private var deleteLabel: String {
        pendingDeletion.count == 1 ? "Delete Task" : "Delete \(pendingDeletion.count) Tasks"
    }
    @ViewState private var importing = false
    @ViewState private var readingBackup = false
    @ViewState private var exporting = false
    @ViewState private var backup: BackupDocument?
    @ViewState private var notice: Notice?

    init(store: TaskStore, index: Binding<WorkspaceIndex>, appearance: Binding<AppAppearance>) {
        self.store = store
        _appearance = appearance
        _index = index
    }

    private struct EditorSession: Identifiable {
        let original: TaskDetails?
        var draft: TaskDetails
        var id: UUID { draft.id }
        var hasChanges: Bool {
            if let original { return draft != original }
            return draft != TaskDetails(id: draft.id, createdAt: draft.createdAt)
        }
    }

    private enum EditorAction {
        case new, open(TaskDetails), close
    }

    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var theme: WorkspaceTheme {
        WorkspaceTheme(dark: colorScheme == .dark, highContrast: contrast == .increased)
    }

    private var projects: [String] {
        index.projects
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let result = index.result(for: view, now: timeline.date, query: .init(project: project, status: statusFilter,
                term: search.trimmingCharacters(in: .whitespacesAndNewlines), order: sortOrder.wrappedValue))
            let visible = result.rows
            let visibleSelection = Set(visible.lazy.filter { selection.contains($0.id) }.map(\.id))
            let selectedTask = visibleSelection.count == 1 ? visible.first { visibleSelection.contains($0.id) } : nil
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                navigation(index.counts(now: timeline.date))
            } detail: {
                Group {
                    if showingSettings {
                        WorkspaceSettings(appearance: $appearance, headings: $headingTypography, textSize: $textSize,
                                          theme: theme, projects: projects, deleteProject: deleteProject,
                                          exportBackup: exportBackup, importBackup: { importing = true })
                            .transition(.opacity)
                    } else {
                        HStack(spacing: 0) {
                            ZStack {
                                main(result, now: timeline.date)
                                    .id(view)
                                    .transition(.opacity)
                            }
                            .animation(reduceMotion ? nil : WorkspaceMotion.page, value: view)
                            if let editor {
                                HStack(spacing: 0) {
                                    Rectangle().fill(theme.line).frame(width: 1)
                                    TaskEditor(
                                        draft: Binding(get: { self.editor?.draft ?? editor.draft }, set: { self.editor?.draft = $0 }),
                                        isNew: editor.original == nil,
                                        projects: projects,
                                        theme: theme,
                                        close: { request(.close) },
                                        save: saveEditor,
                                        delete: { requestDeletion([editor.id]) }
                                    )
                                    .id(editor.id)
                                    .frame(width: 344)
                                }
                                .transition(reduceMotion ? .identity : .offset(x: 18).combined(with: .opacity))
                            }
                        }
                        .clipped()
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : WorkspaceMotion.panel, value: editor != nil)
                .animation(reduceMotion ? nil : WorkspaceMotion.page, value: showingSettings)
                .toolbarBackground(theme.sidebar, for: .windowToolbar)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if let selectedTask, editor == nil, !showingSettings {
                            Button {
                                request(.open(selectedTask))
                            } label: {
                                Label("Task Details", systemImage: "sidebar.right")
                            }
                            .help("Edit the selected task (Return)")
                        }
                        if !showingSettings && !visibleSelection.isEmpty {
                            Button(role: .destructive) { requestDeletion(visibleSelection) } label: {
                                Label("Delete Selected Tasks", systemImage: "trash")
                            }
                            .help("Delete selected tasks")
                        }
                        if !showingSettings {
                            Button { request(.new) } label: {
                                Label("New Task", systemImage: "plus")
                            }
                            .help("New Task (⌘N)")
                        }
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
            .onChange(of: visibleSelection, initial: true) { _, ids in
                if selection != ids { selection = ids }
            }
        }
        .frame(minWidth: 840, minHeight: 540)
        .tint(theme.action)
        .environment(\.headingTypography, headingTypography)
        .environment(\.workspaceTextSize, textSize)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Corner.overlay)
                    .strokeBorder(theme.action, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .padding(Space.sm)
                    .allowsHitTesting(false)
                    .overlay(alignment: .bottom) {
                        Label("Drop a Do backup to import", systemImage: "square.and.arrow.down")
                            .workspaceType(.button)
                            .padding(.horizontal, Space.lg)
                            .padding(.vertical, Space.sm)
                            .background(theme.field, in: RoundedRectangle(cornerRadius: Corner.panel))
                            .padding(Space.lg)
                            .allowsHitTesting(false)
                    }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first, url.isFileURL,
                  url.pathExtension.lowercased() == "json" else { return false }
            importBackup(.success(url))
            return true
        } isTargeted: { dropTargeted = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .findTasks)) { _ in
            showingSettings = false
            sidebarVisibility = .all
            Task { @MainActor in
                await Task.yield()
                searchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchTaskView)) { notification in
            if let destination = notification.object as? TaskView { changeView(destination) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in
            showingSettings = false
            request(.new)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in openSettings() }
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "Do Backup") { result in
            if case .failure(let error) = result { report(error) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], onCompletion: importBackup)
        .alert(item: $notice) { item in
            Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog("Discard unsaved changes?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                if let pendingEditor { changeEditor(pendingEditor) }
                pendingEditor = nil
            }
            Button("Keep Editing", role: .cancel) { pendingEditor = nil }
        }
        .confirmationDialog("\(deleteLabel)?", isPresented: $showDelete, titleVisibility: .visible,
                            presenting: pendingDeletion) { ids in
            Button(deleteLabel, role: .destructive) { deleteTasks(ids) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently removes the selected tasks.")
        }
        .onChange(of: projects) { _, available in
            if !project.isEmpty && !available.contains(project) { project = "" }
        }
    }

    private func navigation(_ counts: [TaskView: Int]) -> some View {
        let destinations: [TaskView] = [.overview, .today, .upcoming, .completed, .milestones, .allTasks]
        return VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Do")
                    .workspaceType(.wordmark)
                    .foregroundStyle(theme.ink)
                    .accessibilityHidden(true)
                sidebarSearch
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.xxl)

            List(selection: Binding<TaskView?>(get: { showingSettings ? nil : view }, set: { destination in
                if let destination { changeView(destination) }
            })) {
                ForEach(destinations) { item in
                    let count = counts[item, default: 0]
                    Label {
                        HStack(spacing: Space.sm) {
                            Text(item.title)
                                .workspaceType(.navigation)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Space.xs)
                            if item != .overview && count > 0 {
                                Text(count, format: .number)
                                    .workspaceType(.metadata)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(count == 1 ? "1 task" : "\(count) tasks")
                            }
                        }
                    } icon: {
                        Image(systemName: item.icon)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 15))
                            .frame(width: 18)
                            .foregroundStyle(view == item ? theme.ink : theme.muted)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, Space.xs)
                    .accessibilityElement(children: .combine)
                    .tag(item)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: Space.xs) {
                Divider().overlay(theme.line)
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .foregroundStyle(showingSettings ? theme.ink : theme.muted)
                        .padding(.horizontal, Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 28)
                        .background {
                            if showingSettings {
                                RoundedRectangle(cornerRadius: Corner.control).fill(theme.ink.opacity(0.10))
                            }
                        }
                }
                .buttonStyle(WorkspaceButtonStyle(theme: theme))
                .accessibilityAddTraits(showingSettings ? .isSelected : [])
                .help("Settings (⌘,)")
            }
            .workspaceType(.navigation)
            .foregroundStyle(theme.muted)
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.lg)
        }
        .background(theme.sidebar)
        .navigationSplitViewColumnWidth(min: 202, ideal: 224, max: 270)
    }

    private var sidebarSearch: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.muted)
                .accessibilityHidden(true)
            TextField("Search tasks", text: $search)
                .textFieldStyle(.plain)
                .workspaceType(.navigation)
                .focused($searchFocused)
                .accessibilityLabel("Search tasks")
                .onExitCommand {
                    search = ""
                    searchFocused = false
                }
            if search.isEmpty {
                Text("⌘K")
                    .workspaceType(.metadata)
                    .foregroundStyle(theme.muted)
                    .accessibilityHidden(true)
            } else {
                Button {
                    search = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.muted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(minHeight: 32)
        .background(WorkspaceFieldSurface(theme: theme, focused: searchFocused))
    }

    private func main(_ result: WorkspaceIndex.Result, now: Date) -> some View {
        let visible = result.rows
        let showSummary = view == .overview && result.sectionCount > 0
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.lg) {
                WorkspaceHeading(title: view.title, color: theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if showSummary {
                    OverviewSummary(total: visible.count, groups: result.summary, theme: theme, navigate: changeView)
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.lg)

            if !tasks.isEmpty {
                tableControls
                    .padding(.horizontal, Space.xl)
                    .padding(.bottom, Space.sm)
            }

            if visible.isEmpty {
                emptyState(hasFilter: !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !project.isEmpty || statusFilter != nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TaskTable(tasks: visible, view: view, now: now, theme: theme, selection: $selection,
                          sortOrder: sortOrder, open: { request(.open($0)) }, toggle: toggleTask, delete: requestDeletion)
                    .padding(.horizontal, Space.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper)
        .accessibilityIdentifier("task-content")
    }

    private var tableControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.sm) {
                projectFilter
                statusMenu
                sortMenu
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                projectFilter
                HStack(spacing: Space.sm) {
                    statusMenu
                    sortMenu
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusMenu: some View {
        TableFilterControl(selection: $statusFilter,
                           options: [nil] + TaskStatus.allCases.map(Optional.some),
                           defaultValue: nil, title: { $0?.rawValue ?? "All statuses" },
                           accessibilityName: "Filter by status", icon: "checkmark.circle", theme: theme)
    }

    private var sortMenu: some View {
        TaskSortControl(rules: sortRules, initialField: view == .milestones ? .key : .due, theme: theme)
    }

    @ViewBuilder
    private var projectFilter: some View {
        if !projects.isEmpty {
            TableFilterControl(selection: $project, options: [""] + projects, defaultValue: "",
                               title: { $0.isEmpty ? "All projects" : $0 },
                               accessibilityName: "Filter by project", icon: "folder", theme: theme,
                               titleLimit: 120)
        }
    }

    private func emptyState(hasFilter: Bool) -> some View {
        let firstTask = tasks.isEmpty
        let noMatches = hasFilter && !firstTask
        return ContentUnavailableView {
            Label(noMatches ? "No Matching Tasks" : firstTask ? "Add Your First Task" : view.emptyTitle,
                  systemImage: noMatches ? "magnifyingglass" : firstTask ? "checkmark.circle" : view.icon)
        } description: {
            Text(noMatches ? "Try a different search or clear your filters." :
                 firstTask ? "A title is all you need to start." : view.emptyMessage)
        } actions: {
            if noMatches {
                Button("Clear Filters") {
                    search = ""
                    project = ""
                    statusFilter = nil
                }
            } else if firstTask {
                VStack(spacing: Space.sm) {
                    Button { request(.new) } label: {
                        Text("New Task")
                            .workspaceType(.button)
                            .foregroundStyle(theme.actionInk)
                            .padding(.horizontal, Space.lg)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(WorkspaceButtonStyle(theme: theme, primary: true))
                    Text("⌘N").workspaceType(.metadata).foregroundStyle(theme.muted)
                        .accessibilityLabel("Command N")
                }
            }
        }
    }

    private func openSettings() {
        searchFocused = false
        showingSettings = true
    }

    private func changeView(_ destination: TaskView) {
        showingSettings = false
        guard view != destination else { return }
        selection = []
        view = destination
    }

    private func request(_ action: EditorAction) {
        if case .open(let task) = action, task.id == editor?.id { return }
        if editor?.hasChanges == true {
            pendingEditor = action
            showDiscard = true
        } else {
            changeEditor(action)
        }
    }

    private func changeEditor(_ action: EditorAction) {
        switch action {
        case .new: editor = EditorSession(original: nil, draft: TaskDetails())
        case .open(let task):
            selection = [task.id]
            editor = EditorSession(original: task, draft: task)
        case .close: editor = nil
        }
    }

    private func saveEditor() {
        guard var draft = editor?.draft else { return }
        do {
            try draft.validate()
            if let existingProject = projects.first(where: { $0.localizedCaseInsensitiveCompare(draft.project) == .orderedSame }) {
                draft.project = existingProject
            }
            var replacement = tasks
            if let index = replacement.firstIndex(where: { $0.id == draft.id }) {
                replacement[index] = draft
            } else {
                replacement.append(draft)
            }
            try commit(replacement)
            selection = [draft.id]
            editor = nil
        } catch {
            report(error)
        }
    }

    private func toggleTask(_ task: TaskDetails) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var replacement = tasks
        replacement[index].setStatus(task.status == .done ? .todo : .done)
        do {
            try commit(replacement, animating: true)
            if let current = editor, current.id == task.id {
                var draft = current.draft
                draft.setStatus(replacement[index].status)
                editor = EditorSession(original: replacement[index], draft: draft)
            }
        } catch {
            report(error)
        }
    }

    private func deleteProject(_ name: String) {
        func unassign(_ task: TaskDetails) -> TaskDetails {
            guard task.project == name else { return task }
            var revised = task
            revised.project = ""
            return revised
        }

        do {
            try commit(tasks.map(unassign))
            if project == name { project = "" }
            if let current = editor {
                editor = EditorSession(original: current.original.map(unassign), draft: unassign(current.draft))
            }
        } catch {
            report(error)
        }
    }

    private func requestDeletion(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDeletion = ids
        showDelete = true
    }

    private func deleteTasks(_ ids: Set<UUID>) {
        do {
            try commit(tasks.filter { !ids.contains($0.id) }, animating: true)
            selection.subtract(ids)
            if let editor, ids.contains(editor.id) { self.editor = nil }
        } catch {
            report(error)
        }
    }

    private func commit(_ replacement: [TaskDetails], animating: Bool = false) throws {
        try store.save(replacement)
        withAnimation(animating && !reduceMotion ? WorkspaceMotion.page : nil) {
            index = WorkspaceIndex(replacement)
        }
    }

    private func exportBackup() {
        do {
            backup = try BackupDocument(tasks: tasks)
            exporting = true
        } catch {
            report(error)
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        guard !readingBackup else {
            notice = Notice(title: "Import in progress", message: "Wait for the current backup to finish importing.")
            return
        }
        readingBackup = true
        Task { @MainActor in
            defer { readingBackup = false }
            do {
                let url = try result.get()
                let imported = try await Task.detached(priority: .userInitiated) {
                    try TaskStore.importBackup(at: url)
                }.value
                let existing = Set(tasks.map(\.id))
                let additions = imported.tasks.filter { !existing.contains($0.id) }
                if !additions.isEmpty { try commit(tasks + additions) }
                let count = additions.count
                let skipped = imported.total - count
                let summary = count == 1 ? "Imported 1 task." : "Imported \(count) tasks."
                notice = Notice(title: "Backup imported", message: skipped == 0 ? summary :
                                summary + " Skipped \(skipped) already present or repeated in the backup.")
            } catch {
                report(error)
            }
        }
    }

    private func report(_ error: Error) {
        notice = Notice(title: "Couldn’t finish", message: error.localizedDescription)
    }
}
