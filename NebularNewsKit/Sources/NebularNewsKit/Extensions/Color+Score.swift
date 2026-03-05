import SwiftUI

extension Color {
    /// Maps a fit score (1–5) to a color, matching the web app's score gradient.
    /// 1 = red (poor fit), 3 = yellow (neutral), 5 = cyan (great fit).
    public static func forScore(_ score: Int?) -> Color {
        switch score {
        case 1: return Color(red: 0.96, green: 0.48, blue: 0.58)  // #f47a94
        case 2: return Color(red: 0.96, green: 0.73, blue: 0.42)  // #f5ba6b
        case 3: return Color(red: 0.95, green: 0.89, blue: 0.42)  // #f2e36b
        case 4: return Color(red: 0.42, green: 0.82, blue: 0.73)  // #6bd1ba
        case 5: return Color(red: 0.35, green: 0.78, blue: 0.90)  // #59c7e5
        default: return .secondary
        }
    }
}
