import SwiftUI

/// Shared bullet row for brief rendering. Used by the Today view's inline
/// brief card and by the detail view in the brief history sheet.
struct BriefBulletRow: View {
    let bullet: CompanionNewsBrief.Bullet

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(bullet.text)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !bullet.sources.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(bullet.sources) { source in
                        NavigationLink(destination: CompanionArticleDetailView(articleId: source.articleId)) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.caption2)
                                Text(source.title ?? "Source")
                                    .font(.caption)
                            }
                            .foregroundStyle(.accent)
                        }
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}
