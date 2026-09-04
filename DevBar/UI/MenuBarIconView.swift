import SwiftUI

struct MenuBarIconView: View {
    let status: ItemStatus
    let issueCount: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "shippingbox.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(DevBarTheme.color(for: status), .primary)
            if issueCount > 0 {
                Text(issueCount > 99 ? "99+" : "\(issueCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(issueCount == 1
            ? "DevBar, \(status.label), 1 item needs attention"
            : "DevBar, \(status.label), \(issueCount) items need attention")
    }
}
