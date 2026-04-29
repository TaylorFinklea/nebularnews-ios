import Testing
@testable import NebularNews

struct FeedSettingsETagTests {
    @Test func computePausedTrueNilNil() {
        // "p1mn" — paused, no cap, no min score
        #expect(FeedSettingsETag.compute(paused: true, maxArticlesPerDay: nil, minScore: nil) == "p1mn")
    }

    @Test func computePausedFalseWithValues() {
        // "p0m100n3" — active, cap 100, min score 3
        #expect(FeedSettingsETag.compute(paused: false, maxArticlesPerDay: 100, minScore: 3) == "p0m100n3")
    }

    @Test func computeMinScoreZeroIsDistinctFromNil() {
        // "p0mn0" — active, no cap, min score explicitly 0 (not nil)
        #expect(FeedSettingsETag.compute(paused: false, maxArticlesPerDay: nil, minScore: 0) == "p0mn0")
    }

    @Test func computeAllNilValues() {
        // "p0mn" — active (false), no cap, no min score
        #expect(FeedSettingsETag.compute(paused: false, maxArticlesPerDay: nil, minScore: nil) == "p0mn")
    }

    @Test func computeHighValues() {
        // Verify decimal string rendering for larger numbers
        #expect(FeedSettingsETag.compute(paused: false, maxArticlesPerDay: 500, minScore: 5) == "p0m500n5")
    }
}
