import Foundation

/// Navigation destination for topic drill-down.
struct TopicDestination: Hashable {
    let id: String
    let name: String
}

/// Maps known tag names to SF Symbols for visual topic cards.
func iconForTag(_ name: String) -> String {
    let lowered = name.lowercased()

    let mapping: [(keywords: [String], icon: String)] = [
        (["artificial intelligence", "ai", "machine learning", "ml", "deep learning"], "brain"),
        (["cybersecurity", "security", "infosec", "hacking"], "shield.lefthalf.filled"),
        (["cloud", "aws", "azure", "gcp", "infrastructure"], "cloud"),
        (["programming", "coding", "software", "development", "engineering"], "chevron.left.forwardslash.chevron.right"),
        (["data", "analytics", "database", "sql"], "chart.bar"),
        (["mobile", "ios", "android", "swift", "kotlin"], "iphone"),
        (["web", "frontend", "javascript", "react", "css"], "globe"),
        (["devops", "ci/cd", "kubernetes", "docker", "deployment"], "gearshape.2"),
        (["science", "research", "physics", "biology"], "atom"),
        (["space", "astronomy", "nasa", "rocket"], "sparkles"),
        (["photography", "camera", "photo", "photos"], "camera"),
        (["design", "ui", "ux", "figma"], "paintbrush"),
        (["crypto", "blockchain", "bitcoin", "ethereum"], "bitcoinsign.circle"),
        (["startup", "venture", "funding", "business"], "chart.line.uptrend.xyaxis"),
        (["gaming", "game", "esports"], "gamecontroller"),
        (["privacy", "surveillance", "encryption"], "lock.shield"),
        (["hardware", "chip", "semiconductor", "processor"], "cpu"),
        (["networking", "protocol", "internet"], "network"),
        (["open source", "oss", "github", "linux"], "terminal"),
    ]

    for entry in mapping {
        for keyword in entry.keywords {
            if lowered.contains(keyword) {
                return entry.icon
            }
        }
    }

    return "tag"
}
