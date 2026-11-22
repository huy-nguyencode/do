import SwiftUI

private typealias ControlState<Value> = SwiftUI.State<Value>

enum WorkspaceMotion {
    static let panel = Animation.smooth(duration: 0.28)
    static let page = Animation.easeInOut(duration: 0.19)
    static let feedback = Animation.easeOut(duration: 0.14)
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
