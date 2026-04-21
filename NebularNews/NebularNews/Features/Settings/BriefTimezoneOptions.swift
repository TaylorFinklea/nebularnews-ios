import Foundation

/// Curated list of IANA timezone identifiers for the news-brief timezone
/// picker. Surfaces the device's current zone at the top, then a representative
/// catalog covering most users. The backend validates any identifier via
/// Intl.DateTimeFormat so unknowns are rejected at PUT time.
enum BriefTimezoneOptions {
    static let all: [String] = {
        let device = TimeZone.current.identifier
        var options = commonZones
        if !options.contains(device) {
            options.insert(device, at: 0)
        } else if let index = options.firstIndex(of: device), index != 0 {
            options.remove(at: index)
            options.insert(device, at: 0)
        }
        return options
    }()

    static func label(for identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else {
            return identifier
        }
        let offset = zone.secondsFromGMT()
        let sign = offset >= 0 ? "+" : "−"
        let absMinutes = abs(offset) / 60
        let hours = absMinutes / 60
        let minutes = absMinutes % 60
        let abbreviation = zone.abbreviation() ?? ""
        let offsetLabel = minutes == 0
            ? String(format: "UTC%@%d", sign, hours)
            : String(format: "UTC%@%d:%02d", sign, hours, minutes)
        let prefix = identifier == TimeZone.current.identifier ? "Current — " : ""
        if abbreviation.isEmpty {
            return "\(prefix)\(identifier) (\(offsetLabel))"
        }
        return "\(prefix)\(identifier) — \(abbreviation) (\(offsetLabel))"
    }

    /// Representative catalog. Keep it short — long pickers are a UX drag.
    /// Users on edge-case zones get auto-inserted via TimeZone.current.
    private static let commonZones: [String] = [
        "UTC",
        "America/Los_Angeles",
        "America/Denver",
        "America/Chicago",
        "America/New_York",
        "America/Halifax",
        "America/Sao_Paulo",
        "Europe/London",
        "Europe/Paris",
        "Europe/Berlin",
        "Europe/Athens",
        "Europe/Moscow",
        "Africa/Johannesburg",
        "Asia/Jerusalem",
        "Asia/Dubai",
        "Asia/Karachi",
        "Asia/Kolkata",
        "Asia/Singapore",
        "Asia/Shanghai",
        "Asia/Tokyo",
        "Australia/Sydney",
        "Pacific/Auckland",
        "Pacific/Honolulu",
    ]
}
