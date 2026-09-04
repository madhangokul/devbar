import AppKit
import SwiftUI

struct ItemRow: View {
    let item: ToolbarItem
    var compact = false
    var buildDuration: TimeInterval? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: openItem) {
            HStack(spacing: 10) {
                Image(systemName: DevBarTheme.symbol(for: item.status))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DevBarTheme.color(for: item.status))
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DevBarTheme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(item.timestamp, style: .relative)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(DevBarTheme.tertiaryText)
                    }

                    HStack(spacing: 5) {
                        Text(item.groupName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DevBarTheme.accent)
                            .lineLimit(1)
                        if !item.subtitle.isEmpty {
                            Text("·")
                                .foregroundStyle(DevBarTheme.tertiaryText)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(DevBarTheme.secondaryText)
                                .lineLimit(1)
                        }

                        if item.phase.isActive || displayBuildDuration != nil {
                            Text("·")
                                .foregroundStyle(DevBarTheme.tertiaryText)
                            BuildTimeLabel(item: item, completedDuration: displayBuildDuration)
                        }
                    }
                }

                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DevBarTheme.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, compact ? 8 : 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(ItemRowButtonStyle(isHovered: isHovered))
        .disabled(item.openURL == nil)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .help(item.openURL == nil ? "No deployment link available" : "Open deployment in your browser")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item.openURL == nil ? "No link is available" : "Opens in your default browser")
    }

    private var accessibilityLabel: String {
        let details = [item.groupName, item.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        let timing = displayBuildDuration.map { ", built in \(DevBarDurationFormatter.string(from: $0))" }
            ?? item.currentBuildElapsed().map { ", running for \(DevBarDurationFormatter.string(from: $0))" }
            ?? ""
        return "\(item.title), \(item.status.label), \(details)\(timing), \(item.timestamp.formatted(.relative(presentation: .named)))"
    }

    private var displayBuildDuration: TimeInterval? {
        buildDuration ?? item.completedBuildDuration
    }

    private func openItem() {
        guard let url = item.openURL else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct BuildTimeLabel: View {
    let item: ToolbarItem
    let completedDuration: TimeInterval?

    var body: some View {
        if let completedDuration {
            Text("Built in \(DevBarDurationFormatter.string(from: completedDuration))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(DevBarTheme.secondaryText)
                .lineLimit(1)
        } else if item.phase.isActive {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text("Running \(DevBarDurationFormatter.string(from: item.currentBuildElapsed(at: context.date) ?? 0))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DevBarTheme.active)
                    .lineLimit(1)
            }
        }
    }
}

private struct ItemRowButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? DevBarTheme.surfacePressed
                    : (isHovered ? DevBarTheme.surface : DevBarTheme.elevated),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isHovered ? DevBarTheme.accent.opacity(0.65) : DevBarTheme.border, lineWidth: 1)
            }
    }
}
