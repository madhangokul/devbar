import AppKit
import SwiftUI

struct AttentionCard: View {
    let items: [ToolbarItem]
    let onDismiss: (String) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DevBarTheme.failed)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Failed deployments")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DevBarTheme.primaryText)
                        Text("\(items.count) deployment\(items.count == 1 ? "" : "s") need attention")
                            .font(.caption2)
                            .foregroundStyle(DevBarTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DevBarTheme.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Failed deployments, \(items.count)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapses the failure list" : "Shows each failed deployment")

            if isExpanded {
                Divider().overlay(DevBarTheme.failed.opacity(0.42))

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        AttentionDeploymentRow(item: item) {
                            onDismiss(item.id)
                        }
                        if index < items.count - 1 {
                            Divider()
                                .overlay(DevBarTheme.border)
                                .padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .background(DevBarTheme.failed.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DevBarTheme.failed.opacity(0.52), lineWidth: 1)
        }
    }
}

private struct AttentionDeploymentRow: View {
    let item: ToolbarItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: DevBarTheme.symbol(for: item.phase))
                .font(.caption)
                .foregroundStyle(DevBarTheme.failed)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DevBarTheme.primaryText)
                    .lineLimit(1)
                Text("\(item.groupName) · \(DevBarTheme.label(for: item.phase))")
                    .font(.caption2)
                    .foregroundStyle(DevBarTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let url = item.openURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DevBarTheme.accent)
                .help("Open failed deployment")
                .accessibilityLabel("Open \(item.title)")
                .accessibilityHint("Opens the deployment in your browser")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DevBarTheme.secondaryText)
            .help("Dismiss this failure locally")
            .accessibilityLabel("Dismiss \(item.title)")
            .accessibilityHint("Hides this deployment until its status changes")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
    }
}

/// Compact provider-neutral progress surface for an active deployment.
///
/// `estimatedProgress` is normalized to 0...1. `elapsedDuration` and
/// `estimatedDuration` are seconds. Callers can inject Open-site behavior or
/// provide `siteURL`; `item.siteURL` is the final fallback.
struct DeploymentProgressOverlay: View {
    let item: ToolbarItem
    let estimatedProgress: Double
    let elapsedDuration: TimeInterval
    let estimatedDuration: TimeInterval
    let siteURL: URL?
    let onDismiss: () -> Void
    let onOpenSite: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    init(
        item: ToolbarItem,
        estimatedProgress: Double,
        elapsedDuration: TimeInterval,
        estimatedDuration: TimeInterval,
        siteURL: URL? = nil,
        onDismiss: @escaping () -> Void,
        onOpenSite: (() -> Void)? = nil
    ) {
        self.item = item
        self.estimatedProgress = estimatedProgress
        self.elapsedDuration = elapsedDuration
        self.estimatedDuration = estimatedDuration
        self.siteURL = siteURL
        self.onDismiss = onDismiss
        self.onOpenSite = onOpenSite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                progressRing

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: DevBarTheme.symbol(for: item.phase))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(overdue ? DevBarTheme.failed : DevBarTheme.active)
                            .accessibilityHidden(true)
                        Text(DevBarTheme.label(for: item.phase))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(overdue ? DevBarTheme.failed : DevBarTheme.active)
                    }
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(DevBarTheme.primaryText)
                        .lineLimit(1)
                    Text(item.subtitle.isEmpty ? item.groupName : "\(item.groupName) · \(item.subtitle)")
                        .font(.caption)
                        .foregroundStyle(DevBarTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DevBarTheme.secondaryText)
                .help("Dismiss progress overlay")
                .accessibilityLabel("Dismiss deployment progress")
            }

            HStack {
                Label(
                    elapsedTitle,
                    systemImage: "stopwatch"
                )
                Spacer()
                Text(durationStatus)
                    .foregroundStyle(overdue ? DevBarTheme.failed : DevBarTheme.secondaryText)
            }
            .font(.caption)
            .monospacedDigit()

            HStack(spacing: 8) {
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: openSite) {
                    Label("Open site", systemImage: "arrow.up.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(DevBarTheme.accent)
                .disabled(onOpenSite == nil && resolvedSiteURL == nil)
                .keyboardShortcut(.defaultAction)
                .help("Open the deployed site")
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(DevBarTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(overdue ? DevBarTheme.failed.opacity(0.72) : DevBarTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 12, y: 5)
        .task(id: overdue) {
            isPulsing = overdue && !reduceMotion
        }
        .onChange(of: reduceMotion) { shouldReduce in
            isPulsing = overdue && !shouldReduce
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Deployment progress for \(item.title)")
    }

    private var progressRing: some View {
        ZStack {
            if overdue {
                Circle()
                    .stroke(DevBarTheme.failed.opacity(isPulsing ? 0.16 : 0.48), lineWidth: 5)
                    .scaleEffect(isPulsing ? 1.16 : 1.02)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
            }

            Circle()
                .stroke(DevBarTheme.border, lineWidth: 5)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    overdue ? DevBarTheme.failed : DevBarTheme.active,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int((clampedProgress * 100).rounded()))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DevBarTheme.primaryText)
        }
        .frame(width: 54, height: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated progress")
        .accessibilityValue("\(Int((clampedProgress * 100).rounded())) percent")
    }

    private var clampedProgress: Double {
        min(1, max(0, estimatedProgress))
    }

    private var overdue: Bool {
        estimatedDuration > 0 && elapsedDuration > estimatedDuration && item.phase.isActive
    }

    private var durationStatus: String {
        if item.phase == .ready {
            return "Deployment complete"
        }
        if item.phase.isFailure {
            return "Deployment stopped"
        }
        guard estimatedDuration > 0 else { return "Estimate unavailable" }
        if overdue {
            return "Overdue by \(DevBarDurationFormatter.string(from: elapsedDuration - estimatedDuration))"
        }
        let remaining = max(0, estimatedDuration - elapsedDuration)
        return "About \(DevBarDurationFormatter.string(from: remaining)) left"
    }

    private var elapsedTitle: String {
        let duration = DevBarDurationFormatter.string(from: elapsedDuration)
        if item.phase == .ready { return "Built in \(duration)" }
        if item.phase.isFailure { return "Stopped after \(duration)" }
        return "Running \(duration)"
    }

    private var resolvedSiteURL: URL? {
        siteURL ?? item.siteURL
    }

    private func openSite() {
        if let onOpenSite {
            onOpenSite()
        } else if let resolvedSiteURL {
            NSWorkspace.shared.open(resolvedSiteURL)
        }
    }
}

enum DevBarDurationFormatter {
    static func string(from duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
        return "\(seconds)s"
    }
}
