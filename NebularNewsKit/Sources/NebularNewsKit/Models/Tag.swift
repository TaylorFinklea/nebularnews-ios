import Foundation
import SwiftData

/// A user-defined or AI-suggested tag for categorizing articles.
@Model
public final class Tag: @unchecked Sendable {
    public var id: String = UUID().uuidString
    public var name: String = ""
    public var nameNormalized: String = ""
    public var slug: String = ""
    public var isCanonical: Bool = false
    public var colorHex: String?
    public var createdAt: Date = Date()

    public var articles: [Article]? = []

    public init(
        id: String = UUID().uuidString,
        name: String,
        colorHex: String? = nil,
        slug: String? = nil,
        isCanonical: Bool = false
    ) {
        self.id = id
        self.name = name
        self.nameNormalized = Tag.normalizeName(name)
        self.slug = Tag.normalizeSlug(slug ?? name)
        self.isCanonical = isCanonical
        self.colorHex = colorHex
        self.createdAt = Date()
    }

    public static func normalizeName(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizeSlug(_ value: String) -> String {
        normalizeName(value)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
