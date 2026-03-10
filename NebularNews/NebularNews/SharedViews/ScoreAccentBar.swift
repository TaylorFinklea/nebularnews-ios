import SwiftUI
import NebularNewsKit

/// Thin vertical accent bar colored by personalization score.
///
/// Unread articles show the full vibrant score color; read articles
/// fade to 30 % opacity of the same hue — never gray.
struct ScoreAccentBar: View {
    let score: Int?
    let isRead: Bool
    var width: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2, style: .continuous)
            .fill(Color.forScore(score))
            .frame(width: width)
            .opacity(isRead ? 0.3 : 1.0)
    }
}
