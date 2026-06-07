import AVFoundation
import Accelerate
import Foundation

enum AudioAnalysisService {
    nonisolated static func analyze(
        recordingURL: URL?,
        transcript: String,
        wordTimings: [RecognizedWordTiming] = [],
        lineAlignment: LineAlignmentState,
        renderedLines: [RenderedScriptLine],
        elapsedTime: TimeInterval,
        wordCount: Int,
        silenceDurations: [TimeInterval]
    ) -> DeliveryAnalysis {
        let transcriptTokens = ScriptRenderService.normalizeTokens(transcript, droppingFillers: false)
        let recognizedCount = max(wordCount, transcriptTokens.count)
        let alignmentCount = estimatedAlignedWordCount(
            lineAlignment: lineAlignment,
            renderedLines: renderedLines
        )
        let measuredWordCount = max(recognizedCount, alignmentCount)
        let speakingDuration = effectiveSpeakingDuration(
            wordTimings: wordTimings,
            fallback: elapsedTime
        )
        let wordsPerMinute = speakingDuration > 0
            ? min(240, max(0, Int(round(Double(measuredWordCount) / (speakingDuration / 60)))))
            : 0
        let pauseAnalysis = makePauseAnalysis(
            silenceDurations: silenceDurations,
            elapsedTime: elapsedTime
        )
        let adherence = makeAdherenceAnalysis(
            lineAlignment: lineAlignment,
            totalLines: renderedLines.count
        )

        let signal = loadSignal(from: recordingURL)
        let windows = makeProsodyWindows(signal: signal)
        let smoothedWindows = smooth(windows: windows)
        let pitch = makePitchAnalysis(windows: smoothedWindows)
        let energy = makeEnergyAnalysis(windows: smoothedWindows)
        let pace = makePaceAnalysis(
            wordsPerMinute: wordsPerMinute,
            wordTimings: wordTimings,
            transitions: lineAlignment.transitions,
            renderedLines: renderedLines
        )

        let consistency = confidenceWeightedScore([
            (pitch.pitchVariationScore, pitch.confidence.value, 0.25),
            (energy.energyVariationScore, energy.confidence.value, 0.15),
            (pace.paceStabilityScore, pace.confidence.value, 0.35),
            (pauseAnalysis.pauseControlScore, pauseAnalysis.confidence.value, 0.15),
            (adherence.scriptAdherenceScore, adherence.confidence.value, 0.10)
        ])

        let summary = makeSummary(
            pitch: pitch,
            energy: energy,
            pace: pace,
            pauses: pauseAnalysis,
            adherence: adherence
        )

        return DeliveryAnalysis(
            pace: pace,
            pauses: pauseAnalysis,
            pitch: pitch,
            energy: energy,
            adherence: adherence,
            deliveryConsistencyScore: consistency,
            summary: summary,
            confidenceByMetric: [
                "pitch": pitch.confidence,
                "energy": energy.confidence,
                "pace": pace.confidence,
                "pauses": pauseAnalysis.confidence,
                "adherence": adherence.confidence
            ]
        )
    }

    nonisolated private static func loadSignal(from url: URL?) -> (samples: [Float], sampleRate: Double)? {
        guard let url else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sourceFormat = file.processingFormat
        let sourceRate = sourceFormat.sampleRate
        guard sourceRate > 0 else { return nil }

        let targetRate = min(16_000, sourceRate)
        let samplingStep = max(1, Int((sourceRate / targetRate).rounded()))
        let effectiveRate = sourceRate / Double(samplingStep)
        let maximumSamples = Int(effectiveRate * 8 * 60)
        let chunkSize: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: chunkSize) else {
            return nil
        }

        var samples: [Float] = []
        samples.reserveCapacity(min(maximumSamples, Int(file.length) / samplingStep))
        var sourceIndex = 0

        while samples.count < maximumSamples {
            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: chunkSize)
            } catch {
                return samples.isEmpty ? nil : (samples, effectiveRate)
            }
            let count = Int(buffer.frameLength)
            guard count > 0, let channel = buffer.floatChannelData?.pointee else { break }

            let chunkStartIndex = sourceIndex
            for index in 0..<count where (chunkStartIndex + index) % samplingStep == 0 {
                samples.append(channel[index])
                if samples.count >= maximumSamples { break }
            }
            sourceIndex += count
        }

        return samples.isEmpty ? nil : (samples, effectiveRate)
    }

    nonisolated private static func makeProsodyWindows(signal: (samples: [Float], sampleRate: Double)?) -> [ProsodyWindow] {
        guard let signal, !signal.samples.isEmpty else { return [] }
        let sampleRate = signal.sampleRate
        let frameSize = max(1024, Int(sampleRate * 0.04))
        let hopSize = max(512, Int(sampleRate * 0.02))
        let minLag = Int(sampleRate / 320)
        let maxLag = max(minLag + 1, Int(sampleRate / 75))

        var frameEnergies: [Double] = []
        var frameStart = 0
        while frameStart + frameSize < signal.samples.count {
            let frame = Array(signal.samples[frameStart..<(frameStart + frameSize)])
            frameEnergies.append(Double(rootMeanSquare(frame)))
            frameStart += hopSize
        }

        let sortedEnergies = frameEnergies.sorted()
        let estimatedNoiseRMS = percentile(sortedEnergies, 0.2)
        let voicedEnergyThreshold = max(0.006, estimatedNoiseRMS * 2.4)

        var windows: [ProsodyWindow] = []
        frameStart = 0
        while frameStart + frameSize < signal.samples.count {
            let frame = Array(signal.samples[frameStart..<(frameStart + frameSize)])
            let rms = rootMeanSquare(frame)
            let zeroCrossingRate = zeroCrossings(frame)
            let pitchEstimate = estimatePitch(frame, sampleRate: sampleRate, minLag: minLag, maxLag: maxLag)
            let signalToNoiseRatio = Double(rms) / max(estimatedNoiseRMS, 0.000_001)
            let voiced =
                Double(rms) > voicedEnergyThreshold &&
                signalToNoiseRatio >= 2.2 &&
                zeroCrossingRate < 0.2 &&
                pitchEstimate.confidence >= 0.5 &&
                pitchEstimate.pitch != nil
            let voicedRatio = voiced ? 1.0 : 0.0
            windows.append(
                ProsodyWindow(
                    startTime: Double(frameStart) / sampleRate,
                    endTime: Double(frameStart + frameSize) / sampleRate,
                    voicedRatio: voicedRatio,
                    rmsEnergy: Double(rms),
                    pitchHz: voiced ? pitchEstimate.pitch : nil,
                    pitchConfidence: voiced
                        ? pitchEstimate.confidence * min(1, signalToNoiseRatio / 4)
                        : 0
                )
            )
            frameStart += hopSize
        }
        return windows
    }

    nonisolated private static func smooth(windows: [ProsodyWindow]) -> [ProsodyWindow] {
        guard windows.count > 2 else { return windows }
        return windows.enumerated().map { index, window in
            let neighbors = windows[max(0, index - 1)...min(windows.count - 1, index + 1)]
            let pitches = neighbors.compactMap(\.pitchHz)
            let energies = neighbors.map(\.rmsEnergy)
            let smoothedPitch = pitches.isEmpty ? nil : pitches.reduce(0, +) / Double(pitches.count)
            let smoothedEnergy = energies.reduce(0, +) / Double(energies.count)
            let confidence = neighbors.map(\.pitchConfidence).reduce(0, +) / Double(neighbors.count)
            return ProsodyWindow(
                startTime: window.startTime,
                endTime: window.endTime,
                voicedRatio: neighbors.map(\.voicedRatio).reduce(0, +) / Double(neighbors.count),
                rmsEnergy: smoothedEnergy,
                pitchHz: smoothedPitch,
                pitchConfidence: confidence
            )
        }
    }

    nonisolated private static func makePauseAnalysis(
        silenceDurations: [TimeInterval],
        elapsedTime: TimeInterval
    ) -> PauseAnalysis {
        let totalSilence = silenceDurations.reduce(0, +)
        let meanPause = silenceDurations.isEmpty ? 0 : totalSilence / Double(silenceDurations.count)
        let largestGap = silenceDurations.max() ?? 0
        let silentRatio = elapsedTime > 0 ? totalSilence / elapsedTime : 0
        let pauseVariance = varianceOfTimeIntervals(silenceDurations)
        let irregularPenalty = min(40.0, pauseVariance * 25)
        let longPausePenalty = max(0, (largestGap - 1.2) * 18)
        let score = max(0, 100 - irregularPenalty - longPausePenalty)
        let confidence = AnalysisConfidence(silenceDurations.isEmpty ? 0.5 : 0.9)
        return PauseAnalysis(
            silenceDurations: silenceDurations,
            largestGapBetweenWords: largestGap,
            silentTimeRatio: silentRatio,
            meanPauseDuration: meanPause,
            pauseControlScore: score,
            confidence: confidence
        )
    }

    nonisolated private static func makePitchAnalysis(windows: [ProsodyWindow]) -> PitchAnalysis {
        let confidentWindows = removePitchOutliers(
            from: windows.filter { $0.pitchConfidence >= 0.5 }
        )
        let rawPitches = confidentWindows.compactMap(\.pitchHz)
        let voicedRatio = windows.isEmpty ? 0 : windows.map(\.voicedRatio).reduce(0, +) / Double(windows.count)
        guard rawPitches.count >= 12 else {
            return PitchAnalysis(
                voicedRatio: voicedRatio,
                medianHz: nil,
                iqrHz: nil,
                spanHz: nil,
                movementRate: 0,
                monotoneSegments: [],
                pitchVariationScore: 0,
                monotonyRiskScore: 100,
                confidence: AnalysisConfidence(voicedRatio * 0.4)
            )
        }

        let rawSorted = rawPitches.sorted()
        let lowFence = percentile(rawSorted, 0.05)
        let highFence = percentile(rawSorted, 0.95)
        let pitched = rawPitches.filter { $0 >= lowFence && $0 <= highFence }
        let sorted = pitched.sorted()
        let median = percentile(sorted, 0.5)
        let q1 = percentile(sorted, 0.25)
        let q3 = percentile(sorted, 0.75)
        let iqr = q3 - q1
        let span = (sorted.last ?? 0) - (sorted.first ?? 0)
        let semitones = sorted.map { 12 * log2(max($0, 1) / max(median, 1)) }
        let semitoneSpread = percentile(semitones.sorted(), 0.75) - percentile(semitones.sorted(), 0.25)
        let chronologicalSemitones = rawPitches.map { 12 * log2(max($0, 1) / max(median, 1)) }
        let movementRate = adjacentMeanDifference(chronologicalSemitones)
        let monotoneSegments = detectMonotoneSegments(windows: confidentWindows, medianPitch: median)
        let spreadScore = triangularScore(value: semitoneSpread, ideal: 4.5, lower: 1.0, upper: 9.0)
        let movementScore = triangularScore(value: movementRate, ideal: 1.2, lower: 0.15, upper: 4.5)
        let monotonePenalty = min(35, Double(monotoneSegments.count) * 7)
        let variationScore = max(0, min(100, spreadScore * 0.7 + movementScore * 0.3 - monotonePenalty))
        let monotonyRisk = max(0, min(100, 100 - variationScore + monotonePenalty * 0.5))
        let meanConfidence = confidentWindows.isEmpty
            ? 0
            : confidentWindows.map(\.pitchConfidence).reduce(0, +) / Double(confidentWindows.count)
        let confidence = AnalysisConfidence(min(1, voicedRatio * 0.55 + meanConfidence * 0.45))
        return PitchAnalysis(
            voicedRatio: voicedRatio,
            medianHz: median,
            iqrHz: iqr,
            spanHz: span,
            movementRate: movementRate,
            monotoneSegments: monotoneSegments,
            pitchVariationScore: variationScore,
            monotonyRiskScore: monotonyRisk,
            confidence: confidence
        )
    }

    nonisolated private static func makeEnergyAnalysis(windows: [ProsodyWindow]) -> EnergyAnalysis {
        guard !windows.isEmpty else {
            return EnergyAnalysis(
                averageRMS: 0,
                rmsVariation: 0,
                energyVariationScore: 0,
                highlightedSegments: [],
                confidence: AnalysisConfidence(0)
            )
        }
        let energies = windows.map(\.rmsEnergy)
        let avg = energies.reduce(0, +) / Double(energies.count)
        let deviation = sqrt(variance(energies))
        let score = max(0, min(100, 100 - max(0, 0.045 - deviation) * 900 - max(0, deviation - 0.14) * 180))
        let threshold = avg + deviation
        let segments = windows.compactMap { window -> ClosedRange<Double>? in
            guard window.rmsEnergy > threshold else { return nil }
            return window.startTime...window.endTime
        }
        let confidence = AnalysisConfidence(avg > 0.002 ? 0.85 : 0.45)
        return EnergyAnalysis(
            averageRMS: avg,
            rmsVariation: deviation,
            energyVariationScore: score,
            highlightedSegments: segments,
            confidence: confidence
        )
    }

    nonisolated private static func makePaceAnalysis(
        wordsPerMinute: Int,
        wordTimings: [RecognizedWordTiming],
        transitions: [LineTransitionRecord],
        renderedLines: [RenderedScriptLine]
    ) -> PaceAnalysis {
        let timingRates = sectionRates(from: wordTimings)
        let ordered = transitions.sorted { $0.timestamp < $1.timestamp }
        let transitionRates: [Int] = zip(ordered, ordered.dropFirst()).compactMap { current, next in
            let duration = max(next.timestamp - current.timestamp, 0.1)
            let lineWordCount = renderedLines
                .filter { $0.index >= current.toLineIndex && $0.index < next.toLineIndex }
                .flatMap(\.normalizedTokens)
                .count
            guard lineWordCount > 0 else { return nil }
            return Int(round(Double(lineWordCount) / (duration / 60)))
        }
        let sections = !timingRates.isEmpty
            ? timingRates
            : (transitionRates.isEmpty ? [wordsPerMinute] : transitionRates)
        let paceStability: Double
        if sections.count >= 2 {
            let values = sections.map(Double.init)
            let median = percentile(values.sorted(), 0.5)
            let deviations = values.map { abs($0 - median) }
            let medianDeviation = percentile(deviations.sorted(), 0.5)
            let relativeDeviation = median > 0 ? medianDeviation / median : 1
            let range = (values.max() ?? median) - (values.min() ?? median)
            paceStability = max(0, min(100, 100 - relativeDeviation * 150 - max(0, range - 35) * 0.45))
        } else {
            paceStability = wordsPerMinute > 0 ? 65 : 0
        }
        let confidence = AnalysisConfidence(
            wordTimings.count >= 30 ? 0.95 : (sections.count >= 2 ? 0.8 : 0.5)
        )
        return PaceAnalysis(
            wordsPerMinute: wordsPerMinute,
            perSectionWordsPerMinute: sections,
            paceStabilityScore: paceStability,
            confidence: confidence
        )
    }

    nonisolated private static func makeAdherenceAnalysis(
        lineAlignment: LineAlignmentState,
        totalLines: Int
    ) -> AdherenceAnalysis {
        let completed = lineAlignment.completedLines.sorted()
        let partial = lineAlignment.partialLines.subtracting(lineAlignment.completedLines).sorted()
        let skipped = lineAlignment.skippedLines.sorted()
        let weak = Array(Set(partial + skipped)).sorted()
        let completionRatio = totalLines > 0 ? Double(completed.count) / Double(totalLines) : 0
        let partialRatio = totalLines > 0 ? Double(partial.count) / Double(totalLines) : 0
        let skipRatio = totalLines > 0 ? Double(skipped.count) / Double(totalLines) : 0
        let score = max(0, min(100, completionRatio * 100 - partialRatio * 18 - skipRatio * 55))
        return AdherenceAnalysis(
            scriptAdherenceScore: score,
            weaklyMatchedLines: weak,
            skippedLines: skipped,
            completedLines: completed,
            partialLines: partial,
            confidence: AnalysisConfidence(totalLines > 0 ? 0.9 : 0.2)
        )
    }

    nonisolated private static func makeSummary(
        pitch: PitchAnalysis,
        energy: EnergyAnalysis,
        pace: PaceAnalysis,
        pauses: PauseAnalysis,
        adherence: AdherenceAnalysis
    ) -> [String] {
        var output: [String] = []

        if pitch.confidence.value < 0.45 || pitch.medianHz == nil {
            output.append("Pitch analysis had low confidence, so the app prioritized pace, pause, and energy feedback.")
        } else if pitch.monotonyRiskScore >= 60 {
            let share = Int(round(min(1, Double(pitch.monotoneSegments.count) / 5) * 100))
            output.append("Pitch variation stayed narrow through \(share)% of tracked voiced segments, suggesting a monotone delivery.")
        } else if pitch.pitchVariationScore >= 70 {
            output.append("Pitch variation stayed in a healthy range without becoming erratic.")
        }

        if pace.perSectionWordsPerMinute.count >= 2 {
            let minRate = pace.perSectionWordsPerMinute.min() ?? pace.wordsPerMinute
            let maxRate = pace.perSectionWordsPerMinute.max() ?? pace.wordsPerMinute
            if maxRate - minRate >= 25 {
                output.append("Speaking rate shifted noticeably across sections, from about \(minRate) to \(maxRate) WPM.")
            }
        }

        if pauses.largestGapBetweenWords >= 1.5 {
            output.append("At least one pause stretched to \(String(format: "%.1f", pauses.largestGapBetweenWords)) seconds, which may feel hesitant.")
        } else if pauses.pauseControlScore >= 75 {
            output.append("Pause placement was relatively controlled, without many long gaps.")
        }

        if adherence.skippedLines.count >= 2 {
            let first = adherence.skippedLines.first ?? 0
            let last = adherence.skippedLines.last ?? 0
            output.append("Lines \(first + 1) to \(last + 1) showed weak script adherence and were likely paraphrased or skipped.")
        } else if adherence.scriptAdherenceScore >= 80 {
            output.append("Script adherence was strong, with most lines completed cleanly.")
        }

        if energy.energyVariationScore < 45 {
            output.append("Energy variation was limited, so emphasis may not be landing consistently.")
        }

        return output
    }

    nonisolated private static func rootMeanSquare(_ frame: [Float]) -> Float {
        guard !frame.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_measqv(frame, 1, &result, vDSP_Length(frame.count))
        return sqrtf(result)
    }

    nonisolated private static func zeroCrossings(_ frame: [Float]) -> Double {
        guard frame.count > 1 else { return 1 }
        let crossings = zip(frame, frame.dropFirst()).filter { pair in
            let (lhs, rhs) = pair
            return (lhs >= 0 && rhs < 0) || (lhs < 0 && rhs >= 0)
        }.count
        return Double(crossings) / Double(frame.count - 1)
    }

    nonisolated private static func estimatePitch(
        _ frame: [Float],
        sampleRate: Double,
        minLag: Int,
        maxLag: Int
    ) -> (pitch: Double?, confidence: Double) {
        guard frame.count > maxLag + 2 else { return (nil, 0) }
        let mean = frame.reduce(0, +) / Float(frame.count)
        var centered = frame.map { $0 - mean }
        var window = [Float](repeating: 0, count: frame.count)
        vDSP_hann_window(&window, vDSP_Length(frame.count), Int32(vDSP_HANN_NORM))
        vDSP_vmul(centered, 1, window, 1, &centered, 1, vDSP_Length(frame.count))

        var bestLag: Int?
        var bestScore: Double = 0
        for lag in minLag...maxLag {
            let count = centered.count - lag
            guard count > 0 else { continue }
            var correlation: Float = 0
            var leadingEnergy: Float = 0
            var laggedEnergy: Float = 0
            centered.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &correlation, vDSP_Length(count))
                vDSP_svesq(base, 1, &leadingEnergy, vDSP_Length(count))
                vDSP_svesq(base.advanced(by: lag), 1, &laggedEnergy, vDSP_Length(count))
            }
            let denominator = sqrt(Double(leadingEnergy) * Double(laggedEnergy))
            guard denominator > 0 else { continue }
            let normalized = Double(correlation) / denominator
            if normalized > bestScore {
                bestScore = normalized
                bestLag = lag
            }
        }

        guard let lag = bestLag, bestScore.isFinite, bestScore >= 0.35 else {
            return (nil, 0)
        }
        let pitch = sampleRate / Double(lag)
        guard pitch.isFinite, pitch >= 75, pitch <= 320 else {
            return (nil, bestScore * 0.2)
        }
        return (pitch, min(1, bestScore))
    }

    nonisolated private static func detectMonotoneSegments(
        windows: [ProsodyWindow],
        medianPitch: Double
    ) -> [ClosedRange<Double>] {
        guard medianPitch > 0 else { return [] }
        var segments: [ClosedRange<Double>] = []
        var currentStart: Double?
        var lastEnd: Double?

        for window in windows {
            guard let pitch = window.pitchHz else {
                if let currentStart, let lastEnd, lastEnd - currentStart >= 1.2 {
                    segments.append(currentStart...lastEnd)
                }
                currentStart = nil
                lastEnd = nil
                continue
            }

            let semitoneDistance = abs(12 * log2(pitch / medianPitch))
            if semitoneDistance < 1.4 {
                currentStart = currentStart ?? window.startTime
                lastEnd = window.endTime
            } else {
                if let currentStart, let lastEnd, lastEnd - currentStart >= 1.2 {
                    segments.append(currentStart...lastEnd)
                }
                currentStart = nil
                lastEnd = nil
            }
        }

        if let currentStart, let lastEnd, lastEnd - currentStart >= 1.2 {
            segments.append(currentStart...lastEnd)
        }

        return segments
    }

    nonisolated private static func removePitchOutliers(from windows: [ProsodyWindow]) -> [ProsodyWindow] {
        guard windows.count >= 5 else { return windows }
        return windows.enumerated().filter { index, window in
            guard let pitch = window.pitchHz else { return false }
            let lower = max(0, index - 2)
            let upper = min(windows.count - 1, index + 2)
            let neighborhood = windows[lower...upper].compactMap(\.pitchHz).sorted()
            guard neighborhood.count >= 3 else { return true }
            let localMedian = percentile(neighborhood, 0.5)
            let semitoneDistance = abs(12 * log2(pitch / max(localMedian, 1)))
            return semitoneDistance <= 7
        }.map(\.element)
    }

    nonisolated private static func percentile(_ sorted: [Double], _ percentile: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = max(0, min(Double(sorted.count - 1), percentile * Double(sorted.count - 1)))
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    nonisolated private static func adjacentMeanDifference(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let differences = zip(values, values.dropFirst()).map { abs($1 - $0) }
        return differences.reduce(0, +) / Double(differences.count)
    }

    nonisolated private static func varianceOfTimeIntervals(_ values: [TimeInterval]) -> Double {
        return variance(values.map { Double($0) })
    }

    nonisolated private static func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    }

    nonisolated private static func effectiveSpeakingDuration(
        wordTimings: [RecognizedWordTiming],
        fallback: TimeInterval
    ) -> TimeInterval {
        guard let first = wordTimings.first, let last = wordTimings.last else {
            return fallback
        }
        return max(1, last.endTime - first.startTime)
    }

    nonisolated private static func estimatedAlignedWordCount(
        lineAlignment: LineAlignmentState,
        renderedLines: [RenderedScriptLine]
    ) -> Int {
        let completedWords = renderedLines
            .filter {
                lineAlignment.completedLines.contains($0.index) &&
                !lineAlignment.skippedLines.contains($0.index)
            }
            .reduce(0) { $0 + $1.normalizedTokens.count }

        guard renderedLines.indices.contains(lineAlignment.activeLineIndex) else {
            return completedWords
        }

        let activeLine = renderedLines[lineAlignment.activeLineIndex]
        guard !lineAlignment.completedLines.contains(activeLine.index) else {
            return completedWords
        }

        let conservativeProgress = max(0, min(0.85, lineAlignment.currentScore))
        let activeWords = Int((Double(activeLine.normalizedTokens.count) * conservativeProgress).rounded(.down))
        return completedWords + activeWords
    }

    nonisolated private static func sectionRates(from timings: [RecognizedWordTiming]) -> [Int] {
        guard timings.count >= 12 else { return [] }
        let sectionWordCount = 12
        var rates: [Int] = []
        var start = 0

        while start + sectionWordCount <= timings.count {
            let end = min(start + sectionWordCount, timings.count)
            let section = timings[start..<end]
            guard let first = section.first, let last = section.last else { break }
            let duration: TimeInterval
            if end < timings.count {
                duration = max(2, timings[end].startTime - first.startTime)
            } else {
                let intervals = zip(section, section.dropFirst()).map {
                    $1.startTime - $0.startTime
                }
                let typicalInterval = intervals.isEmpty
                    ? max(last.duration, 0.2)
                    : percentile(intervals.sorted(), 0.5)
                duration = max(2, last.endTime + typicalInterval - first.startTime)
            }
            let rate = Int(round(Double(section.count) / (duration / 60)))
            if (45...260).contains(rate) {
                rates.append(rate)
            }
            start += sectionWordCount
        }
        return rates
    }

    nonisolated private static func triangularScore(
        value: Double,
        ideal: Double,
        lower: Double,
        upper: Double
    ) -> Double {
        if value <= ideal {
            return max(0, min(100, (value - lower) / max(ideal - lower, 0.001) * 100))
        }
        return max(0, min(100, (upper - value) / max(upper - ideal, 0.001) * 100))
    }

    nonisolated private static func confidenceWeightedScore(
        _ metrics: [(score: Double, confidence: Double, weight: Double)]
    ) -> Double {
        let usable = metrics.filter { $0.confidence >= 0.3 }
        let totalWeight = usable.reduce(0) { $0 + $1.confidence * $1.weight }
        guard totalWeight > 0 else { return 0 }
        return usable.reduce(0) {
            $0 + $1.score * $1.confidence * $1.weight
        } / totalWeight
    }
}
