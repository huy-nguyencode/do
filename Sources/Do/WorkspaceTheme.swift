import SwiftUI

struct WorkspaceTheme {
    let dark: Bool
    let highContrast: Bool

    var paper: Color { color(light: 0xFFFFFF, dark: 0x141414) }
    var sidebar: Color { color(light: 0xF7F7F7, dark: 0x1C1C1C) }
    var inspector: Color { color(light: 0xFAFAFA, dark: 0x242424) }
    var field: Color { color(light: 0xFFFFFF, dark: 0x1C1C1C) }
    var ink: Color { color(light: 0x171717, dark: 0xF5F5F5) }
    var muted: Color { color(light: 0x666666, dark: 0xA3A3A3) }
    var action: Color { ink }
    var actionInk: Color { color(light: 0xFFFFFF, dark: 0x171717) }
    var focus: Color { color(light: 0x444444, dark: 0xD4D4D4) }

    var line: Color {
        highContrast ? color(light: 0x777777, dark: 0x999999) : color(light: 0xE5E5E5, dark: 0x353535)
    }

    var fieldOutline: Color { highContrast ? line : color(light: 0xD4D4D4, dark: 0x505050) }

    private func color(light: UInt32, dark: UInt32) -> Color {
        let hex = self.dark ? dark : light
        return Color(.sRGB,
                     red: Double((hex >> 16) & 0xff) / 255,
                     green: Double((hex >> 8) & 0xff) / 255,
                     blue: Double(hex & 0xff) / 255,
                     opacity: 1)
    }
}

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Corner {
    static let control: CGFloat = 6
    static let panel: CGFloat = 10
    static let overlay: CGFloat = 14
}

enum HeadingTypography: String, CaseIterable {
    case serif = "Serif"
    case sansSerif = "Sans serif"
    case monospaced = "Monospaced"

    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .sansSerif: .default
        case .monospaced: .monospaced
        }
    }
}

enum WorkspaceTextSize: String, CaseIterable {
    case compact = "Compact"
    case standard = "Standard"
    case large = "Large"
    case extraLarge = "Extra large"

    var multiplier: CGFloat {
        switch self {
        case .compact: 0.9
        case .standard: 1
        case .large: 1.15
        case .extraLarge: 1.28
        }
    }
}

private struct HeadingTypographyKey: EnvironmentKey {
    static let defaultValue: HeadingTypography = .serif
}

private struct WorkspaceTextSizeKey: EnvironmentKey {
    static let defaultValue: WorkspaceTextSize = .standard
}

extension EnvironmentValues {
    var headingTypography: HeadingTypography {
        get { self[HeadingTypographyKey.self] }
        set { self[HeadingTypographyKey.self] = newValue }
    }

    var workspaceTextSize: WorkspaceTextSize {
        get { self[WorkspaceTextSizeKey.self] }
        set { self[WorkspaceTextSizeKey.self] = newValue }
    }
}

enum WorkspaceType {
    case page, panel, section, task, navigation, body, metadata, button

    var size: CGFloat {
        switch self {
        case .page: 38
        case .panel: 23
        case .section: 16
        case .task, .body: 14
        case .navigation, .button: 13
        case .metadata: 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .page, .body, .metadata: .regular
        case .task, .navigation: .medium
        case .panel, .section, .button: .semibold
        }
    }
}

extension View {
    func workspaceType(_ role: WorkspaceType) -> some View {
        modifier(WorkspaceTypography(role: role))
    }
}

private struct WorkspaceTypography: ViewModifier {
    let role: WorkspaceType

    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    @Environment(\.headingTypography) private var headingTypography
    @Environment(\.workspaceTextSize) private var textSize

    func body(content: Content) -> some View {
        content.font(.system(size: role.size * scale * textSize.multiplier, weight: role.weight,
                             design: role == .page ? headingTypography.design : .default))
    }
}

struct WorkspaceHeading: View {
    let title: String
    let color: Color
    var role: WorkspaceType = .page

    var body: some View {
        Text(title)
            .workspaceType(role)
            .tracking(role == .page ? -0.5 : 0)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}
