import Foundation

extension Date {
    /// Relative time string: "2m ago", "3h ago", "Yesterday", "Mar 4".
    public var relativeDisplay: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 172800 {
            return "Yesterday"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = Calendar.current.isDate(self, equalTo: now, toGranularity: .year)
                ? "MMM d"
                : "MMM d, yyyy"
            return formatter.string(from: self)
        }
    }
}
