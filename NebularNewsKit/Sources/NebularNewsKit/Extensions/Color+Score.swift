import SwiftUI

extension Color {
    /// Maps a fit score (1–5) to a color, matching the web app's score gradient.
    /// 1 = soft red (poor fit), 3 = violet (neutral), 5 = mint green (great fit).
    public static func forScore(_ score: Int?) -> Color {
        switch score {
        case 1: return Color(red: 0.99, green: 0.65, blue: 0.65)  // #fca5a5
        case 2: return Color(red: 0.99, green: 0.73, blue: 0.45)  // #fdba74
        case 3: return Color(red: 0.77, green: 0.71, blue: 0.99)  // #c4b5fd
        case 4: return Color(red: 0.40, green: 0.91, blue: 0.98)  // #67e8f9
        case 5: return Color(red: 0.53, green: 0.94, blue: 0.67)  // #86efac
        default: return .secondary
        }
    }
}
