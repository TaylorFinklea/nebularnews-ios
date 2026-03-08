import SwiftUI

/// Section header with title and subtitle, used across Today, Feed, and Discover tabs.
struct DashboardSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(NebularTypography.sectionHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
