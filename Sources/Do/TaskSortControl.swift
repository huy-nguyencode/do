import SwiftUI

private typealias SortState<Value> = SwiftUI.State<Value>

struct TaskSortControl: View {
    @Binding var rules: [TaskSortRule]
    let initialField: TaskSortField
    let theme: WorkspaceTheme
    @SortState private var showingRules = false

    private var unusedFields: [TaskSortField] {
        TaskSortField.allCases.filter { field in !rules.contains { $0.field == field } }
    }

    var body: some View {
        Button {
            showingRules.toggle()
        } label: {
            TableControlLabel(title: rules.isEmpty ? "Sort" : rules.count == 1 ? "1 sort" : "\(rules.count) sorts",
                              icon: "arrow.up.arrow.down", active: !rules.isEmpty, theme: theme)
        }
        .buttonStyle(WorkspaceButtonStyle(theme: theme))
        .fixedSize()
        .accessibilityLabel("Sort tasks")
        .accessibilityValue(rules.isEmpty ? "Default order" : "\(rules.count) rules")
        .popover(isPresented: $showingRules, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Space.sm) {
                WorkspaceHeading(title: "Sort rules", color: theme.ink, role: .section)
                Text("Rules are applied from top to bottom.")
                    .workspaceType(.metadata)
                    .foregroundStyle(theme.muted)
                ForEach(Array(rules.enumerated()), id: \.element.field) { position, rule in
                    ruleRow(rule, position: position)
                }
                Divider()
                HStack {
                    Button {
                        if let field = unusedFields.contains(initialField) ? initialField : unusedFields.first {
                            rules.append(TaskSortRule(field: field))
                        }
                    } label: {
                        Label("Add sort", systemImage: "plus")
                    }
                    .disabled(unusedFields.isEmpty)
                    Spacer()
                    Button("Clear sorts") { rules.removeAll() }
                        .disabled(rules.isEmpty)
                }
            }
            .padding(Space.lg)
            .frame(width: 396)
        }
    }

    private func ruleRow(_ rule: TaskSortRule, position: Int) -> some View {
        HStack(spacing: Space.sm) {
            Text("\(position + 1)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Priority \(position + 1)")

            Picker("Sort field", selection: Binding(get: { rule.field }, set: { field in
                if let index = rules.firstIndex(of: rule) { rules[index].field = field }
            })) {
                ForEach(TaskSortField.allCases.filter { $0 == rule.field || unusedFields.contains($0) }, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .labelsHidden()
            .frame(width: 102)

            Picker("Sort direction", selection: Binding(get: { rule.order }, set: { order in
                if let index = rules.firstIndex(of: rule) { rules[index].order = order }
            })) {
                Text(directionLabel(.forward, for: rule.field)).tag(SortOrder.forward)
                Text(directionLabel(.reverse, for: rule.field)).tag(SortOrder.reverse)
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            iconButton("Move \(rule.field.rawValue) up", icon: "chevron.up") { move(rule, by: -1) }
                .disabled(position == 0)
            iconButton("Move \(rule.field.rawValue) down", icon: "chevron.down") { move(rule, by: 1) }
                .disabled(position == rules.count - 1)
            iconButton("Remove \(rule.field.rawValue) sort", icon: "xmark") {
                rules.removeAll { $0.field == rule.field }
            }
        }
    }

    private func iconButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).labelStyle(.iconOnly) }
            .buttonStyle(.borderless)
            .help(title)
    }

    private func move(_ rule: TaskSortRule, by offset: Int) {
        guard let index = rules.firstIndex(of: rule), rules.indices.contains(index + offset) else { return }
        rules.swapAt(index, index + offset)
    }

    private func directionLabel(_ order: SortOrder, for field: TaskSortField) -> String {
        switch field {
        case .due, .key, .created: order == .forward ? "Oldest first" : "Newest first"
        case .title, .project: order == .forward ? "A to Z" : "Z to A"
        case .status, .progress: order == .forward ? "Ascending" : "Descending"
        }
    }
}
