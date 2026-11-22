import SwiftUI

private typealias EditorState<Value> = SwiftUI.State<Value>

struct TaskEditor: View {
    @Binding var draft: TaskDetails
    let isNew: Bool
    let projects: [String]
    let theme: WorkspaceTheme
    let close: () -> Void
    let save: () -> Void
    let delete: () -> Void

    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EditorState private var enteringProject = false
    @EditorState private var showingProjects = false
    @EditorState private var progressText: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, project, notes, progress }

    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    identityFields
                    dueDateField
                    statusFields
                    notesField
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.lg)
            }
            footer
        }
        .background(theme.inspector)
        .tint(theme.action)
        .task {
            await Task.yield()
            if isNew { focus = .title }
        }
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            WorkspaceHeading(title: isNew ? "New task" : "Task details", color: theme.ink, role: .panel)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(WorkspaceButtonStyle(theme: theme))
            .accessibilityLabel("Close task editor")
            .help("Close (Esc)")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                fieldLabel("Task title")
                TextField("Task title", text: $draft.title,
                          prompt: Text("What needs doing?").foregroundStyle(theme.muted))
                    .textFieldStyle(.plain)
                    .workspaceType(.body)
                    .foregroundStyle(theme.ink)
                    .accessibilityLabel("Task title")
                    .focused($focus, equals: .title)
                    .onSubmit { if canSave { save() } }
                    .padding(.horizontal, Space.md)
                    .frame(minHeight: 38)
                    .background(WorkspaceFieldSurface(theme: theme, focused: focus == .title))
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                fieldLabel("Project")
                projectField
            }
        }
    }

    private var projectField: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button { showingProjects = true } label: {
                WorkspacePickerLabel(icon: "folder", theme: theme, focused: showingProjects || focus == .project,
                                     expanded: showingProjects) {
                    Text(draft.project.isEmpty ? "Choose or create a project" : draft.project)
                        .foregroundStyle(draft.project.isEmpty ? theme.muted : theme.ink)
                        .lineLimit(1)
                }
            }
            .buttonStyle(WorkspaceButtonStyle(theme: theme))
            .accessibilityLabel("Project")
            .accessibilityValue(draft.project.isEmpty ? "No project" : draft.project)
            .popover(isPresented: $showingProjects, arrowEdge: .leading) {
                projectChoices
            }

            if enteringProject {
                TextField("New project name", text: $draft.project)
                    .textFieldStyle(.plain)
                    .workspaceType(.body)
                    .focused($focus, equals: .project)
                    .padding(.horizontal, Space.md)
                    .frame(minHeight: 36)
                    .background(WorkspaceFieldSurface(theme: theme, focused: focus == .project))
                    .onSubmit {
                        if !draft.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            enteringProject = false
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : WorkspaceMotion.page, value: enteringProject)
    }

    private var projectChoices: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xs) {
                    projectChoice("", title: "No Project")
                    ForEach(projects, id: \.self) { name in
                        projectChoice(name, title: name)
                    }
                }
            }
            .frame(height: CGFloat(min(projects.count + 1, 7)) * 32)
            Divider().overlay(theme.line)
            Button {
                showingProjects = false
                enteringProject = true
                Task { @MainActor in
                    await Task.yield()
                    focus = .project
                }
            } label: {
                Label("New Project…", systemImage: "plus")
                    .padding(.horizontal, Space.sm)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            }
            .buttonStyle(WorkspaceButtonStyle(theme: theme))
        }
        .workspaceType(.body)
        .foregroundStyle(theme.ink)
        .padding(Space.sm)
        .frame(width: 260)
        .background(theme.inspector)
    }

    private func projectChoice(_ value: String, title: String) -> some View {
        Button {
            draft.project = value
            enteringProject = false
            showingProjects = false
        } label: {
            HStack {
                Text(title).lineLimit(1)
                Spacer(minLength: Space.xs)
                if draft.project == value {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Space.sm)
            .frame(minHeight: 28)
        }
        .buttonStyle(WorkspaceButtonStyle(theme: theme))
        .accessibilityAddTraits(draft.project == value ? .isSelected : [])
    }

    private var dueDateField: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            fieldLabel("Due date")
            TaskScheduleField(task: $draft, theme: theme)
        }
    }

    private var statusFields: some View {
        let options = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 2))
        return VStack(alignment: .leading, spacing: Space.sm) {
            fieldLabel("Status")
            options {
                statusButton(.todo, icon: "circle")
                statusButton(.inProgress, icon: "circle.lefthalf.filled")
                statusButton(.done, icon: "checkmark.circle")
            }
            .background(alignment: .bottom) {
                Rectangle().fill(theme.line).frame(height: 1)
            }
            HStack(spacing: Space.sm) {
                Text("Progress")
                    .workspaceType(.metadata)
                    .foregroundStyle(theme.muted)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { Double(draft.progress) },
                                      set: { progressText = nil; draft.setProgress(Int($0.rounded())) }),
                       in: 0...100) { Text("Progress") }
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityValue("\(draft.progress) percent")
                TextField("Progress percentage", text: Binding(
                    get: { progressText ?? String(draft.progress) },
                    set: { input in
                        if input.isEmpty { progressText = ""; return }
                        guard input.allSatisfy({ $0 >= "0" && $0 <= "9" }), let value = Int(input) else { return }
                        draft.setProgress(value)
                        progressText = String(draft.progress)
                    }))
                    .textFieldStyle(.plain)
                    .workspaceType(.metadata)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, Space.xs)
                    .frame(width: 44, height: 24)
                    .background(WorkspaceFieldSurface(theme: theme, focused: focus == .progress))
                    .focused($focus, equals: .progress)
                    .onSubmit { progressText = nil }
                    .onChange(of: focus) { _, field in
                        if field != .progress { progressText = nil }
                    }
                Text("%").workspaceType(.metadata).foregroundStyle(theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.top, 2)
        }
    }

    private func statusButton(_ status: TaskStatus, icon: String) -> some View {
        let selected = draft.status == status
        return Button { progressText = nil; draft.setStatus(status) } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                Text(status.rawValue)
                    .lineLimit(1)
            }
            .workspaceType(.navigation)
            .foregroundStyle(selected ? theme.action : theme.muted)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 33)
            .overlay(alignment: .bottom) {
                if selected {
                    Rectangle().fill(theme.action).frame(height: 2)
                }
            }
        }
        .buttonStyle(WorkspaceButtonStyle(theme: theme))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion ? nil : WorkspaceMotion.feedback, value: selected)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            fieldLabel("Notes")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.notes)
                    .workspaceType(.body)
                    .foregroundStyle(theme.ink)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .focused($focus, equals: .notes)
                    .accessibilityLabel("Notes")
                    .padding(Space.sm)

                if draft.notes.isEmpty {
                    Text("Add a note…")
                        .workspaceType(.body)
                        .foregroundStyle(theme.muted)
                        .padding(.leading, Space.md)
                        .padding(.top, Space.sm)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 112)
            .background(WorkspaceFieldSurface(theme: theme, focused: focus == .notes))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !isNew {
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.muted)
                        .frame(width: 36, height: 34)
                }
                .buttonStyle(WorkspaceButtonStyle(theme: theme))
                .accessibilityLabel("Delete task")
                .help("Delete Task")
            }
            Button(action: save) {
                Text(isNew ? "Add task" : "Save changes")
                    .workspaceType(.button)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .overlay(alignment: .trailing) {
                        Text("⌘S")
                            .workspaceType(.metadata)
                            .padding(.trailing, Space.md)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(canSave ? theme.actionInk : theme.muted)
            }
            .buttonStyle(WorkspaceButtonStyle(theme: theme, primary: true))
            .keyboardShortcut("s")
            .disabled(!canSave)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.md)
        .background(alignment: .top) {
            Rectangle().fill(theme.line).frame(height: 1)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title).workspaceType(.navigation).foregroundStyle(theme.ink)
    }

}
