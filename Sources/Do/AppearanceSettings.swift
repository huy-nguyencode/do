import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private typealias SettingsState<Value> = SwiftUI.State<Value>

struct WorkspaceSettings: View {
    @Binding var appearance: AppAppearance
    @Binding var headings: HeadingTypography
    @Binding var textSize: WorkspaceTextSize
    let theme: WorkspaceTheme
    let projects: [String]
    let deleteProject: (String) -> Void
    @SettingsState private var pendingProject: String?
    let exportBackup: () -> Void
    let importBackup: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                WorkspaceHeading(title: "Settings", color: theme.ink)

                VStack(alignment: .leading, spacing: Space.md) {
                    WorkspaceHeading(title: "Appearance", color: theme.ink, role: .section)
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    Text("System follows the appearance selected in macOS.")
                        .workspaceType(.metadata)
                        .foregroundStyle(theme.muted)
                }

                Divider().overlay(theme.line)

                VStack(alignment: .leading, spacing: Space.md) {
                    WorkspaceHeading(title: "Typography", color: theme.ink, role: .section)
                    Picker("Text size", selection: $textSize) {
                        ForEach(WorkspaceTextSize.allCases, id: \.self) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    Picker("Page headings", selection: $headings) {
                        ForEach(HeadingTypography.allCases, id: \.self) { family in
                            Text(family.rawValue).tag(family)
                        }
                    }
                }

                Divider().overlay(theme.line)

                VStack(alignment: .leading, spacing: Space.md) {
                    WorkspaceHeading(title: "Projects", color: theme.ink, role: .section)
                    if projects.isEmpty {
                        Text("No projects yet. Create one from the task editor.")
                            .workspaceType(.body)
                            .foregroundStyle(theme.muted)
                    }
                    ForEach(projects, id: \.self) { name in
                        HStack {
                            Label(name, systemImage: "folder")
                                .workspaceType(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Delete…", role: .destructive) { pendingProject = name }
                                .accessibilityLabel("Delete project \(name)")
                        }
                    }
                }

                Divider().overlay(theme.line)

                VStack(alignment: .leading, spacing: Space.md) {
                    WorkspaceHeading(title: "Backups", color: theme.ink, role: .section)
                    Text("Export a copy of your tasks or import tasks from a Do backup.")
                        .workspaceType(.body)
                        .lineSpacing(Space.xs)
                        .foregroundStyle(theme.muted)
                    HStack(spacing: Space.md) {
                        Button("Export Backup…", action: exportBackup)
                            .keyboardShortcut("e", modifiers: [.command, .shift])
                        Button("Import Backup…", action: importBackup)
                    }
                }
            }
            .workspaceType(.body)
            .frame(maxWidth: 620, alignment: .leading)
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.paper)
        .alert("Delete project?", isPresented: Binding(
            get: { pendingProject != nil },
            set: { if !$0 { pendingProject = nil } }
        ), presenting: pendingProject) { name in
            Button("Delete Project", role: .destructive) { deleteProject(name) }
            Button("Cancel", role: .cancel) {}
        } message: { name in
            Text("Tasks assigned to “\(name)” will stay in Do with no project.")
        }
    }
}
