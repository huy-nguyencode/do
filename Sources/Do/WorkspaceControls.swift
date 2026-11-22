import SwiftUI

private typealias ControlState<Value> = SwiftUI.State<Value>

enum WorkspaceMotion {
    static let panel = Animation.smooth(duration: 0.28)
    static let page = Animation.easeInOut(duration: 0.19)
    static let feedback = Animation.easeOut(duration: 0.14)
}

struct TableFilterControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let defaultValue: Value
    let title: (Value) -> String
    let accessibilityName: String
    let icon: String
    let theme: WorkspaceTheme
    var titleLimit: CGFloat? = nil
    @ControlState private var showingOptions = false

    var body: some View {
        Button {
            showingOptions.toggle()
        } label: {
            TableControlLabel(title: title(selection), icon: icon, active: selection != defaultValue,
                              theme: theme, titleLimit: titleLimit)
        }
        .buttonStyle(WorkspaceButtonStyle(theme: theme))
        .fixedSize()
        .help(title(selection))
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(title(selection))
        .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: Space.xs) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            selection = option
                            showingOptions = false
                        } label: {
                            HStack(spacing: Space.sm) {
                                Image(systemName: "checkmark")
                                    .opacity(option == selection ? 1 : 0)
                                    .accessibilityHidden(true)
                                Text(title(option))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .workspaceType(.navigation)
                            .padding(.horizontal, Space.sm)
                            .frame(minHeight: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(WorkspaceButtonStyle(theme: theme))
                        .accessibilityAddTraits(option == selection ? .isSelected : [])
                    }
                }
                .padding(Space.xs)
            }
            .frame(width: 224, height: min(CGFloat(options.count) * 36 + Space.sm, 260))
            .onExitCommand { showingOptions = false }
        }
    }
}

struct TableControlLabel: View {
    let title: String
    let icon: String
    let active: Bool
    let theme: WorkspaceTheme
    var titleLimit: CGFloat? = nil

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            Image(systemName: icon)
                .foregroundStyle(active ? theme.ink : theme.muted)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: titleLimit, alignment: .leading)
            Image(systemName: "chevron.down")
                .imageScale(.small)
                .foregroundStyle(theme.muted)
                .accessibilityHidden(true)
        }
        .workspaceType(.navigation)
        .foregroundStyle(theme.ink)
        .padding(.horizontal, Space.sm)
        .frame(minHeight: 28)
        .background {
            RoundedRectangle(cornerRadius: Corner.control)
                .fill(active ? theme.ink.opacity(0.10) : theme.ink.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: Corner.control)
                        .strokeBorder(active ? theme.fieldOutline : theme.line)
                }
        }
    }
}

struct WorkspaceFieldSurface: View {
    let theme: WorkspaceTheme
    let focused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Corner.control)
            .fill(theme.field)
            .overlay {
                RoundedRectangle(cornerRadius: Corner.control)
                    .strokeBorder(focused ? theme.focus : theme.fieldOutline, lineWidth: focused ? 2 : 1)
            }
    }
}

struct WorkspaceButtonStyle: ButtonStyle {
    let theme: WorkspaceTheme
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        WorkspaceButtonBody(configuration: configuration, theme: theme, primary: primary)
    }
}

private struct WorkspaceButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let theme: WorkspaceTheme
    let primary: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @ControlState private var hovered = false

    var body: some View {
        let filled = primary && enabled
        let hoverFill = theme.ink.opacity(0.07)
        return configuration.label
            .background {
                RoundedRectangle(cornerRadius: Corner.control)
                    .fill(filled ? theme.action : primary ? theme.field : hovered && enabled ? hoverFill : .clear)
                    .overlay {
                        if configuration.isPressed {
                            RoundedRectangle(cornerRadius: Corner.control)
                                .fill((filled ? theme.actionInk : theme.ink).opacity(0.12))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Corner.control)
                            .strokeBorder(primary && !enabled ? theme.line : .clear)
                    }
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: Corner.control)
                        .strokeBorder(theme.focus, lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Corner.control))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : WorkspaceMotion.feedback, value: hovered)
            .animation(reduceMotion ? nil : WorkspaceMotion.feedback, value: configuration.isPressed)
    }
}


struct WorkspacePickerLabel<Content: View>: View {
    let icon: String
    let theme: WorkspaceTheme
    let focused: Bool
    var expanded = false
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: icon)
                .frame(width: 17)
                .accessibilityHidden(true)
            content()
            Spacer(minLength: Space.xs)
            Image(systemName: "chevron.down")
                .workspaceType(.metadata)
                .rotationEffect(.degrees(expanded && !reduceMotion ? 180 : 0))
                .animation(reduceMotion ? nil : WorkspaceMotion.feedback, value: expanded)
                .accessibilityHidden(true)
        }
        .workspaceType(.body)
        .foregroundStyle(theme.muted)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(minHeight: 38)
        .background(WorkspaceFieldSurface(theme: theme, focused: focused))
    }
}


struct TaskCompletionButton: View {
    let task: TaskDetails
    var compact = false
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var done: Bool { task.status == .done }

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Image(systemName: "circle")
                    .opacity(done ? 0 : 1)
                Image(systemName: "checkmark.circle.fill")
                    .opacity(done ? 1 : 0)
                    .scaleEffect(done || reduceMotion ? 1 : 0.78)
            }
            .font(.system(size: compact ? 15 : 20, weight: compact ? .regular : .light))
            .foregroundStyle(.secondary)
            .frame(width: compact ? 24 : 25, height: compact ? 26 : 29)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : WorkspaceMotion.feedback, value: done)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(done ? "Reopen \(task.title)" : "Complete \(task.title)")
        .help(done ? "Reopen task" : "Mark as done")
    }
}
