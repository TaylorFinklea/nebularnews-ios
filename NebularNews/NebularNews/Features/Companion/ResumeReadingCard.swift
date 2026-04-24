import SwiftUI

/// "Continue reading" card surfaced on Today view when the user has an
/// in-progress article (read position between 1% and 94%, not marked read).
/// Tapping pushes the article detail view; that view will auto-scroll to the
/// saved position on appear.
struct ResumeReadingCard: View {
    let resume: CompanionResumeReading

    var body: some View {
        GlassCard(style: .standard) {
            HStack(alignment: .center, spacing: 12) {
                if let imageUrl = resume.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "book.pages")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Continue reading")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.accent)
                        .textCase(.uppercase)
                    Text(resume.title ?? "Untitled article")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    progressBar
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.accent)
                        .frame(width: max(4, geo.size.width * CGFloat(resume.positionPercent) / 100.0))
                }
            }
            .frame(height: 3)
            Text("\(resume.positionPercent)%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
