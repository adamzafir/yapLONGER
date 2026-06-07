import Foundation

struct ScriptDocument: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var bodyText: String
    var lastAccessed: Date
    var version: Int
    var annotations: [ScriptAnnotation]
    var derivedCues: [DerivedCue]

    init(
        id: UUID = UUID(),
        title: String,
        bodyText: String,
        lastAccessed: Date = Date(),
        version: Int = 1,
        annotations: [ScriptAnnotation] = [],
        derivedCues: [DerivedCue] = []
    ) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.lastAccessed = lastAccessed
        self.version = version
        self.annotations = annotations
        self.derivedCues = derivedCues
    }
}

enum AnnotationKind: String, Codable, Hashable, CaseIterable {
    case comment
    case emphasis
    case pause
    case slowDown
    case speedUp
    case smile
}

struct ScriptAnnotation: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: AnnotationKind
    let quotedText: String
    let note: String
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        quotedText: String,
        note: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.quotedText = quotedText
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct DerivedCue: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: AnnotationKind
    let phrase: String
    let rationale: String

    init(id: UUID = UUID(), kind: AnnotationKind, phrase: String, rationale: String) {
        self.id = id
        self.kind = kind
        self.phrase = phrase
        self.rationale = rationale
    }
}

struct RenderedScriptLine: Identifiable, Codable, Hashable {
    let id: UUID
    let index: Int
    let displayText: String
    let normalizedTokens: [String]

    init(index: Int, displayText: String, normalizedTokens: [String]) {
        self.id = UUID()
        self.index = index
        self.displayText = displayText
        self.normalizedTokens = normalizedTokens
    }
}

struct TranscriptToken: Identifiable, Codable, Hashable {
    let id: UUID
    let value: String
    let normalizedValue: String
    let timestamp: TimeInterval

    init(value: String, normalizedValue: String, timestamp: TimeInterval) {
        self.id = UUID()
        self.value = value
        self.normalizedValue = normalizedValue
        self.timestamp = timestamp
    }
}

struct RecognizedWordTiming: Codable, Hashable {
    let word: String
    let startTime: TimeInterval
    let duration: TimeInterval

    nonisolated var endTime: TimeInterval {
        startTime + duration
    }
}

enum AlignmentDriftState: String, Codable, Hashable {
    case aligned
    case recovering
    case drifting
}

struct LineMatchRecord: Codable, Hashable {
    let lineIndex: Int
    let score: Double
    let isCompleted: Bool
    let isSkipped: Bool
    let timestamp: TimeInterval
}

struct LineTransitionRecord: Codable, Hashable {
    let fromLineIndex: Int
    let toLineIndex: Int
    let timestamp: TimeInterval
    let score: Double
    let skippedLines: [Int]
}

struct LineAlignmentSnapshot: Codable, Hashable {
    let timestamp: TimeInterval
    let activeLineIndex: Int
    let currentScore: Double
    let nextScore: Double
    let driftState: AlignmentDriftState
}

struct LineAlignmentState: Codable, Hashable {
    var activeLineIndex: Int
    var currentScore: Double
    var nextScore: Double
    var driftState: AlignmentDriftState
    var completedLines: Set<Int>
    var partialLines: Set<Int>
    var skippedLines: Set<Int>
    var repeatedLineDetections: Int
    var transitions: [LineTransitionRecord]
    var scoreHistory: [LineMatchRecord]
    var snapshots: [LineAlignmentSnapshot]

    static let initial = LineAlignmentState(
        activeLineIndex: 0,
        currentScore: 0,
        nextScore: 0,
        driftState: .aligned,
        completedLines: [],
        partialLines: [],
        skippedLines: [],
        repeatedLineDetections: 0,
        transitions: [],
        scoreHistory: [],
        snapshots: []
    )
}

struct AnalysisConfidence: Codable, Hashable {
    let value: Double

    nonisolated init(_ value: Double) {
        self.value = max(0, min(1, value))
    }
}

struct ProsodyWindow: Codable, Hashable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let voicedRatio: Double
    let rmsEnergy: Double
    let pitchHz: Double?
    let pitchConfidence: Double
}

struct PauseAnalysis: Codable, Hashable {
    let silenceDurations: [TimeInterval]
    let largestGapBetweenWords: TimeInterval
    let silentTimeRatio: Double
    let meanPauseDuration: Double
    let pauseControlScore: Double
    let confidence: AnalysisConfidence
}

struct PitchAnalysis: Codable, Hashable {
    let voicedRatio: Double
    let medianHz: Double?
    let iqrHz: Double?
    let spanHz: Double?
    let movementRate: Double
    let monotoneSegments: [ClosedRange<Double>]
    let pitchVariationScore: Double
    let monotonyRiskScore: Double
    let confidence: AnalysisConfidence
}

struct EnergyAnalysis: Codable, Hashable {
    let averageRMS: Double
    let rmsVariation: Double
    let energyVariationScore: Double
    let highlightedSegments: [ClosedRange<Double>]
    let confidence: AnalysisConfidence
}

struct PaceAnalysis: Codable, Hashable {
    let wordsPerMinute: Int
    let perSectionWordsPerMinute: [Int]
    let paceStabilityScore: Double
    let confidence: AnalysisConfidence
}

struct AdherenceAnalysis: Codable, Hashable {
    let scriptAdherenceScore: Double
    let weaklyMatchedLines: [Int]
    let skippedLines: [Int]
    let completedLines: [Int]
    let partialLines: [Int]
    let confidence: AnalysisConfidence
}

struct DeliveryAnalysis: Codable, Hashable {
    let pace: PaceAnalysis
    let pauses: PauseAnalysis
    let pitch: PitchAnalysis
    let energy: EnergyAnalysis
    let adherence: AdherenceAnalysis
    let deliveryConsistencyScore: Double
    let summary: [String]
    let confidenceByMetric: [String: AnalysisConfidence]
}

struct PracticeSession: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceScriptID: UUID?
    let sourceScriptVersion: Int
    let sourceScriptTitle: String
    let recordingURL: URL?
    let transcriptText: String
    let renderedLines: [RenderedScriptLine]
    let lineAlignment: LineAlignmentState
    let transcriptTokens: [TranscriptToken]
    let elapsedTime: TimeInterval
    let wordCount: Int
    let createdAt: Date
    let analysis: DeliveryAnalysis
}
