import Foundation

final class TeleprompterAlignmentEngine {
    private let debounceWindow: TimeInterval = 0.16
    private let driftResetThreshold = 0.12

    private(set) var state: LineAlignmentState = .initial

    private var lines: [RenderedScriptLine] = []
    private var candidateAdvanceTimestamp: TimeInterval?
    private var candidateTargetLine: Int?
    private var candidateObservationCount = 0
    private var lastTranscriptTokens: [String] = []

    func configure(lines: [RenderedScriptLine]) {
        self.lines = lines
        self.state = .initial
        self.candidateAdvanceTimestamp = nil
        self.candidateTargetLine = nil
        self.candidateObservationCount = 0
        self.lastTranscriptTokens = []
    }

    func processTranscript(_ transcript: String, at timestamp: TimeInterval) {
        guard !lines.isEmpty else { return }
        let tokens = ScriptRenderService.normalizeTokens(transcript)
        guard !tokens.isEmpty else { return }
        if tokens == lastTranscriptTokens {
            state.repeatedLineDetections += 1
        }
        lastTranscriptTokens = tokens

        let currentIndex = min(max(state.activeLineIndex, 0), lines.count - 1)
        let currentEvidence = evidence(for: tokens, in: lines[currentIndex].normalizedTokens)
        let lookAhead: [(Int, LineEvidence)]
        if currentIndex + 1 < lines.count {
            lookAhead = ((currentIndex + 1)...min(currentIndex + 3, lines.count - 1))
                .map { index in
                    (index, evidence(for: tokens, in: lines[index].normalizedTokens))
                }
        } else {
            lookAhead = []
        }
        let nextEvidence = lookAhead.first?.1 ?? .empty
        let bestLookAheadScore = lookAhead.map(\.1.score).max() ?? 0

        let currentScore = currentEvidence.score
        let nextScore = nextEvidence.score
        let drift = driftState(
            for: currentScore,
            nextScore: nextScore,
            bestLookAheadScore: bestLookAheadScore
        )

        state.currentScore = currentScore
        state.nextScore = nextScore
        state.snapshots.append(
            LineAlignmentSnapshot(
                timestamp: timestamp,
                activeLineIndex: currentIndex,
                currentScore: currentScore,
                nextScore: nextScore,
                driftState: drift
            )
        )

        let currentCompleted = currentEvidence.canAdvanceCurrentLine
        let nextCompleted = nextEvidence.canAutoAdvanceToNextLine

        if currentCompleted {
            state.completedLines.insert(currentIndex)
        } else if currentEvidence.hasAnchorWord || currentEvidence.hasEndingEvidence {
            state.partialLines.insert(currentIndex)
        }

        state.scoreHistory.append(
            LineMatchRecord(
                lineIndex: currentIndex,
                score: currentScore,
                isCompleted: currentCompleted,
                isSkipped: false,
                timestamp: timestamp
            )
        )

        if currentIndex + 1 < lines.count {
            if nextCompleted || nextEvidence.meaningfulMatchCount > 0 {
                state.partialLines.insert(currentIndex + 1)
            }
            state.scoreHistory.append(
                LineMatchRecord(
                    lineIndex: currentIndex + 1,
                    score: nextScore,
                    isCompleted: nextCompleted,
                    isSkipped: false,
                    timestamp: timestamp
                )
            )
        }

        state.driftState = drift
        if drift == .drifting {
            clearCandidate()
            return
        }

        let targetLine = decideTargetLine(
            currentIndex: currentIndex,
            currentEvidence: currentEvidence,
            lookAhead: lookAhead
        )
        guard let targetLine else {
            clearCandidate()
            return
        }

        if candidateTargetLine != targetLine {
            candidateTargetLine = targetLine
            candidateAdvanceTimestamp = timestamp
            candidateObservationCount = 1
            return
        }
        candidateObservationCount += 1

        let requiredObservations = targetLine > currentIndex + 1 ? 3 : 2
        guard
            candidateObservationCount >= requiredObservations,
            let started = candidateAdvanceTimestamp,
            timestamp - started >= debounceWindow
        else {
            return
        }

        advance(
            to: targetLine,
            timestamp: timestamp,
            score: targetLine == currentIndex + 1
                ? max(currentScore, nextScore)
                : (lookAhead.first(where: { $0.0 == targetLine })?.1.score ?? nextScore)
        )
        clearCandidate()
    }

    private func driftState(
        for currentScore: Double,
        nextScore: Double,
        bestLookAheadScore: Double
    ) -> AlignmentDriftState {
        if max(currentScore, max(nextScore, bestLookAheadScore)) < driftResetThreshold {
            return .drifting
        }
        if bestLookAheadScore > currentScore && bestLookAheadScore >= 0.32 {
            return .recovering
        }
        return .aligned
    }

    private func decideTargetLine(
        currentIndex: Int,
        currentEvidence: LineEvidence,
        lookAhead: [(Int, LineEvidence)]
    ) -> Int? {
        if currentEvidence.canAdvanceCurrentLine {
            return min(currentIndex + 1, lines.count - 1)
        }
        if let recovery = lookAhead
            .filter({
                $0.1.canAutoAdvanceToNextLine &&
                ($0.0 == currentIndex + 1 || $0.1.meaningfulMatchCount >= 2)
            })
            .max(by: { $0.1.score < $1.1.score }) {
            return recovery.0
        }
        return nil
    }

    private func advance(to newLineIndex: Int, timestamp: TimeInterval, score: Double) {
        let boundedTarget = min(max(newLineIndex, 0), lines.count - 1)
        let previous = state.activeLineIndex
        guard boundedTarget > previous else { return }

        let skipped = boundedTarget > previous + 1 ? Array((previous + 1)..<boundedTarget) : []
        skipped.forEach { state.skippedLines.insert($0) }
        state.transitions.append(
            LineTransitionRecord(
                fromLineIndex: previous,
                toLineIndex: boundedTarget,
                timestamp: timestamp,
                score: score,
                skippedLines: skipped
            )
        )
        state.activeLineIndex = boundedTarget
    }

    private func evidence(for transcriptTokens: [String], in lineTokens: [String]) -> LineEvidence {
        guard !transcriptTokens.isEmpty, !lineTokens.isEmpty else { return .empty }

        let transcriptWindow = Array(transcriptTokens.suffix(max(10, lineTokens.count + 5)))
        let meaningfulLineTokens = lineTokens.filter { isMeaningful($0) }
        let orderedMatchCount = longestOrderedMatch(
            lineTokens: meaningfulLineTokens,
            transcriptTokens: transcriptWindow
        )
        let meaningfulMatches = meaningfulLineTokens.filter { lineToken in
            transcriptWindow.contains { tokensMatch(lineToken, $0) }
        }
        let tailTokens = Array(meaningfulLineTokens.suffix(min(3, meaningfulLineTokens.count)))
        let endingMatchCount = tailTokens.filter { lineToken in
            transcriptWindow.contains { tokensMatch(lineToken, $0) }
        }.count
        let lastMeaningfulWord = tailTokens.last
        let lastWordMatched = lastMeaningfulWord.map { lastWord in
            transcriptWindow.suffix(4).contains { tokensMatch(lastWord, $0) }
        } ?? false
        let hasAnchorWord = !meaningfulMatches.isEmpty
        let hasEndingEvidence = endingMatchCount > 0

        let lineLength = max(meaningfulLineTokens.count, 1)
        let orderedRatio = Double(orderedMatchCount) / Double(lineLength)
        let anchorRatio = Double(Set(meaningfulMatches).count) / Double(lineLength)
        let endingRatio = Double(endingMatchCount) / Double(max(tailTokens.count, 1))
        let score = min(1, orderedRatio * 0.65 + anchorRatio * 0.2 + endingRatio * 0.15)

        let minimumOrderedRatio: Double
        switch meaningfulLineTokens.count {
        case 0...3:
            minimumOrderedRatio = 0.66
        case 4...7:
            minimumOrderedRatio = 0.5
        default:
            minimumOrderedRatio = 0.38
        }

        let canAdvanceCurrentLine =
            (orderedRatio >= minimumOrderedRatio && orderedMatchCount >= min(2, lineLength)) ||
            (orderedRatio >= max(0.3, minimumOrderedRatio - 0.1) && endingRatio >= 0.5)
        let canAutoAdvanceToNextLine =
            (orderedRatio >= minimumOrderedRatio && orderedMatchCount >= min(2, lineLength)) ||
            (orderedRatio >= max(0.34, minimumOrderedRatio - 0.08) && lastWordMatched)

        return LineEvidence(
            score: score,
            meaningfulMatchCount: meaningfulMatches.count,
            hasAnchorWord: hasAnchorWord,
            hasEndingEvidence: hasEndingEvidence,
            lastWordMatched: lastWordMatched,
            canAdvanceCurrentLine: canAdvanceCurrentLine,
            canAutoAdvanceToNextLine: canAutoAdvanceToNextLine
        )
    }

    private func isMeaningful(_ token: String) -> Bool {
        token.count > 2 || token.allSatisfy(\.isNumber)
    }

    private func tokensMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let shorterCount = min(lhs.count, rhs.count)
        guard shorterCount >= 4 else { return false }
        let allowedDistance = shorterCount >= 8 ? 2 : 1
        if editDistance(lhs, rhs) <= allowedDistance {
            return true
        }

        // Speech recognition often changes a word ending while preserving its stem.
        return shorterCount >= 6 && lhs.prefix(4) == rhs.prefix(4)
    }

    private func longestOrderedMatch(
        lineTokens: [String],
        transcriptTokens: [String]
    ) -> Int {
        guard !lineTokens.isEmpty, !transcriptTokens.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: transcriptTokens.count + 1)

        for lineToken in lineTokens {
            var current = [Int](repeating: 0, count: transcriptTokens.count + 1)
            for index in transcriptTokens.indices {
                if tokensMatch(lineToken, transcriptTokens[index]) {
                    current[index + 1] = previous[index] + 1
                } else {
                    current[index + 1] = max(previous[index + 1], current[index])
                }
            }
            previous = current
        }
        return previous.last ?? 0
    }

    private func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                current.append(min(previous[rightIndex + 1] + 1, current[rightIndex] + 1, substitution))
            }
            previous = current
        }
        return previous.last ?? max(left.count, right.count)
    }

    private func clearCandidate() {
        candidateAdvanceTimestamp = nil
        candidateTargetLine = nil
        candidateObservationCount = 0
    }
}

private struct LineEvidence {
    let score: Double
    let meaningfulMatchCount: Int
    let hasAnchorWord: Bool
    let hasEndingEvidence: Bool
    let lastWordMatched: Bool
    let canAdvanceCurrentLine: Bool
    let canAutoAdvanceToNextLine: Bool

    static let empty = LineEvidence(
        score: 0,
        meaningfulMatchCount: 0,
        hasAnchorWord: false,
        hasEndingEvidence: false,
        lastWordMatched: false,
        canAdvanceCurrentLine: false,
        canAutoAdvanceToNextLine: false
    )
}
