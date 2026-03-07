import Foundation

public enum SignalName: String, CaseIterable, Codable, Sendable {
    case topicAffinity = "topic_affinity"
    case sourceReputation = "source_reputation"
    case contentFreshness = "content_freshness"
    case contentDepth = "content_depth"
    case authorAffinity = "author_affinity"
    case tagMatchRatio = "tag_match_ratio"
}

public let preferenceBackedSignalNames: Set<SignalName> = [
    .topicAffinity,
    .sourceReputation,
    .authorAffinity,
    .tagMatchRatio
]

public enum LocalScoreStatus: String, Codable, Sendable {
    case ready
    case insufficientSignal = "insufficient_signal"
}

public struct StoredSignalScore: Codable, Sendable, Hashable, Identifiable {
    public let signal: SignalName
    public let rawValue: Double
    public let normalizedValue: Double
    public let isDataBacked: Bool

    public var id: String { signal.rawValue }

    public init(signal: SignalName, rawValue: Double, normalizedValue: Double, isDataBacked: Bool) {
        self.signal = signal
        self.rawValue = rawValue
        self.normalizedValue = normalizedValue
        self.isDataBacked = isDataBacked
    }
}

public struct LocalSignalWeight: Sendable, Hashable {
    public let signal: SignalName
    public let weight: Double
    public let sampleCount: Int

    public init(signal: SignalName, weight: Double, sampleCount: Int) {
        self.signal = signal
        self.weight = weight
        self.sampleCount = sampleCount
    }
}

public struct AlgorithmicScore: Sendable {
    public let score: Int
    public let signals: [StoredSignalScore]
    public let weights: [LocalSignalWeight]
    public let confidence: Double
    public let preferenceConfidence: Double
    public let dataBackedSignalCount: Int
    public let preferenceBackedSignalCount: Int
    public let weightedAverage: Double
    public let status: LocalScoreStatus

    public init(
        score: Int,
        signals: [StoredSignalScore],
        weights: [LocalSignalWeight],
        confidence: Double,
        preferenceConfidence: Double,
        dataBackedSignalCount: Int,
        preferenceBackedSignalCount: Int,
        weightedAverage: Double,
        status: LocalScoreStatus
    ) {
        self.score = score
        self.signals = signals
        self.weights = weights
        self.confidence = confidence
        self.preferenceConfidence = preferenceConfidence
        self.dataBackedSignalCount = dataBackedSignalCount
        self.preferenceBackedSignalCount = preferenceBackedSignalCount
        self.weightedAverage = weightedAverage
        self.status = status
    }
}

public let defaultSignalWeights: [SignalName: Double] = [
    .topicAffinity: 1.0,
    .sourceReputation: 0.8,
    .contentFreshness: 0.6,
    .contentDepth: 0.5,
    .authorAffinity: 0.7,
    .tagMatchRatio: 0.9
]

public let scoringLearningRate = 0.1
public let scoringDampingFactor = 50.0
public let minDataBackedSignalsToPublish = 2
public let minPreferenceBackedSignalsToPublish = 1
public let sourceReputationVoteWeight = 1.5
public let sourceReputationPriorWeight = 5.0

public func computeAlgorithmicScore(
    signals: [StoredSignalScore],
    weights: [LocalSignalWeight]
) -> AlgorithmicScore {
    let weightBySignal = Dictionary(uniqueKeysWithValues: weights.map { ($0.signal, $0) })

    var weightedSum = 0.0
    var totalWeight = 0.0
    var dataBackedSignalCount = 0
    var preferenceBackedSignalCount = 0

    for signal in signals {
        let weight = weightBySignal[signal.signal]?.weight ?? defaultSignalWeights[signal.signal] ?? 1.0
        weightedSum += weight * signal.normalizedValue
        totalWeight += weight
        if signal.isDataBacked {
            dataBackedSignalCount += 1
            if preferenceBackedSignalNames.contains(signal.signal) {
                preferenceBackedSignalCount += 1
            }
        }
    }

    let weightedAverage = totalWeight > 0 ? (weightedSum / totalWeight) : 0.5
    let rawScore = 1 + (4 * weightedAverage)
    let score = max(1, min(5, Int(rawScore.rounded())))
    let confidence = signals.isEmpty ? 0 : Double(dataBackedSignalCount) / Double(signals.count)
    let preferenceSignalCount = preferenceBackedSignalNames.count
    let preferenceConfidence = preferenceSignalCount == 0
        ? 0
        : Double(preferenceBackedSignalCount) / Double(preferenceSignalCount)
    let status: LocalScoreStatus =
        dataBackedSignalCount >= minDataBackedSignalsToPublish &&
        preferenceBackedSignalCount >= minPreferenceBackedSignalsToPublish
        ? .ready
        : .insufficientSignal

    return AlgorithmicScore(
        score: score,
        signals: signals,
        weights: weights,
        confidence: confidence,
        preferenceConfidence: preferenceConfidence,
        dataBackedSignalCount: dataBackedSignalCount,
        preferenceBackedSignalCount: preferenceBackedSignalCount,
        weightedAverage: weightedAverage,
        status: status
    )
}
