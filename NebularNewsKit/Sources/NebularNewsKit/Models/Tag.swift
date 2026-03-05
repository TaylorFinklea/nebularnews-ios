import Foundation
import SwiftData

/// A user-defined or AI-suggested tag for categorizing articles.
@Model
public final class Tag {
    public var id: String = UUID().uuidString
    public var name: String = ""
    public var nameNormalized: String = ""
    public var colorHex: String?
    public var createdAt: Date = Date()

    public var articles: [Article]? = []

    public init(name: String, colorHex: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.nameNormalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}
