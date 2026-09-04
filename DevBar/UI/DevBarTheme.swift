import SwiftUI

enum DevBarTheme {
    // Intentionally quiet, fixed DevOps palette for the compact menu-bar surface.
    // Status is always reinforced with a symbol and label, never color alone.
    static let background = Color(red: 0.094, green: 0.102, blue: 0.114)
    static let elevated = Color(red: 0.129, green: 0.141, blue: 0.157)
    static let surface = Color(red: 0.155, green: 0.169, blue: 0.188)
    static let surfacePressed = Color(red: 0.190, green: 0.207, blue: 0.227)
    static let border = Color(red: 0.255, green: 0.275, blue: 0.306)

    static let primaryText = Color(red: 0.906, green: 0.918, blue: 0.933)
    static let secondaryText = Color(red: 0.675, green: 0.698, blue: 0.733)
    static let tertiaryText = Color(red: 0.505, green: 0.537, blue: 0.580)
    static let accent = Color(red: 0.565, green: 0.631, blue: 0.710)

    static let healthy = Color(red: 0.357, green: 0.631, blue: 0.471)
    static let active = Color(red: 0.718, green: 0.576, blue: 0.325)
    static let failed = Color(red: 0.725, green: 0.420, blue: 0.420)
    static let neutral = Color(red: 0.475, green: 0.506, blue: 0.545)

    static func color(for status: ItemStatus) -> Color {
        switch status {
        case .good: healthy
        case .warning: active
        case .error: failed
        case .neutral: neutral
        }
    }

    static func symbol(for status: ItemStatus) -> String {
        switch status {
        case .good: "checkmark.circle.fill"
        case .warning: "clock.fill"
        case .error: "exclamationmark.triangle.fill"
        case .neutral: "minus.circle.fill"
        }
    }

    static func label(for phase: ItemPhase) -> String {
        switch phase {
        case .ready: "Ready"
        case .building: "Building"
        case .queued: "Queued"
        case .initializing: "Initializing"
        case .error: "Failed"
        case .canceled: "Canceled"
        case .blocked: "Blocked"
        case .unknown: "Unknown"
        }
    }

    static func symbol(for phase: ItemPhase) -> String {
        switch phase {
        case .ready: "checkmark.circle.fill"
        case .building: "hammer.fill"
        case .queued: "clock.fill"
        case .initializing: "ellipsis.circle.fill"
        case .error: "xmark.circle.fill"
        case .canceled: "nosign"
        case .blocked: "hand.raised.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

struct DevBarCardModifier: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(
                highlighted ? DevBarTheme.surface : DevBarTheme.elevated,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DevBarTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func devBarCard(highlighted: Bool = false) -> some View {
        modifier(DevBarCardModifier(highlighted: highlighted))
    }
}

struct DevBarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 30, height: 30)
            .background(
                configuration.isPressed ? DevBarTheme.surfacePressed : DevBarTheme.elevated,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DevBarTheme.border, lineWidth: 1)
            }
            .foregroundStyle(DevBarTheme.primaryText)
    }
}

struct DevBarSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DevBarTheme.primaryText)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(DevBarTheme.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
