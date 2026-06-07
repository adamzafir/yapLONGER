import AVFoundation
import Accelerate
import Combine
import Foundation
import Speech

private final class AudioBufferWriter {
    private let file: AVAudioFile
    private let lock = NSLock()

    init(url: URL, format: AVAudioFormat) throws {
        file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        try? file.write(from: buffer)
    }
}

@MainActor
final class PracticeSessionController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var transcript = ""
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var liveWordsPerMinute = 0
    @Published private(set) var activeLineIndex = 0
    @Published private(set) var driftState: AlignmentDriftState = .aligned
    @Published private(set) var shouldFinishSession = false
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let alignmentEngine = TeleprompterAlignmentEngine()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioWriter: AudioBufferWriter?
    private var recordingURL: URL?
    private var timer: Timer?
    private var startedAt: Date?
    private var renderedLines: [RenderedScriptLine] = []
    private var wordTimings: [RecognizedWordTiming] = []
    private var silenceDurations: [TimeInterval] = []
    private var isSilent = true
    private var hasDetectedSpeech = false
    private var silenceStartedAt: Date?
    private var noiseFloorSamples: [Float] = []
    private var noiseFloor: Float = -55
    private var smoothedLevel: Float = -60
    private var speechFrameCount = 0
    private var silenceFrameCount = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard
                    let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                    AVAudioSession.InterruptionType(rawValue: rawType) == .began,
                    self?.isRecording == true
                else {
                    return
                }
                self?.errorMessage = "Recording was stopped because the audio session was interrupted."
                self?.shouldFinishSession = true
            }
            .store(in: &cancellables)
        #endif
    }

    var formattedElapsedTime: String {
        let total = Int(elapsedTime.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var recognizedWordCount: Int {
        wordTimings.count
    }

    func configure(lines: [RenderedScriptLine]) {
        renderedLines = lines
        alignmentEngine.configure(lines: lines)
        activeLineIndex = 0
        driftState = .aligned
    }

    func start() async {
        guard !isRecording, !renderedLines.isEmpty else { return }
        errorMessage = nil

        guard await requestPermissions() else {
            errorMessage = "Microphone and speech recognition access are required for voice-following practice."
            return
        }

        resetSession()

        do {
            guard let recognizer, recognizer.isAvailable else {
                throw PracticeSessionError.speechRecognitionUnavailable
            }

            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .voiceChat, options: [.allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            let input = audioEngine.inputNode
            if !input.isVoiceProcessingEnabled {
                try? input.setVoiceProcessingEnabled(true)
            }
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw PracticeSessionError.audioInputUnavailable
            }

            let url = makeRecordingURL()
            let writer = try AudioBufferWriter(url: url, format: format)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.contextualStrings = contextualPhrases()

            recordingURL = url
            audioWriter = writer
            recognitionRequest = request

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                writer.write(buffer)
                let level = Self.decibels(in: buffer)
                Task { @MainActor [weak self] in
                    self?.processAudioLevel(level)
                }
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    if let result {
                        self?.processTranscription(result.bestTranscription)
                    }
                    if let error, self?.isRecording == true {
                        self?.errorMessage = "Speech recognition paused: \(error.localizedDescription)"
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            startedAt = Date()
            startTimer()
        } catch {
            tearDownAudio()
            errorMessage = "Could not start practice: \(error.localizedDescription)"
        }
    }

    func stopAndAnalyze() async -> Review? {
        guard isRecording else { return nil }

        elapsedTime = Date().timeIntervalSince(startedAt ?? Date())
        isRecording = false
        isAnalyzing = true
        timer?.invalidate()
        timer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        try? await Task.sleep(for: .milliseconds(700))
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioWriter = nil

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        guard elapsedTime >= 2, !transcript.isEmpty else {
            if let recordingURL {
                try? FileManager.default.removeItem(at: recordingURL)
            }
            isAnalyzing = false
            errorMessage = "That practice was too short to grade. Speak for a few seconds and try again."
            return nil
        }

        let analysisURL = recordingURL
        let analysisTranscript = transcript
        let analysisWordTimings = wordTimings
        let analysisAlignment = alignmentEngine.state
        let analysisLines = renderedLines
        let analysisElapsedTime = elapsedTime
        let analysisSilences = silenceDurations

        let analysis = await Task.detached(priority: .userInitiated) {
            AudioAnalysisService.analyze(
                recordingURL: analysisURL,
                transcript: analysisTranscript,
                wordTimings: analysisWordTimings,
                lineAlignment: analysisAlignment,
                renderedLines: analysisLines,
                elapsedTime: analysisElapsedTime,
                wordCount: analysisWordTimings.count,
                silenceDurations: analysisSilences
            )
        }.value

        let pitchConfidence = analysis.pitch.confidence.value
        let review = Review(
            cis: Int(analysis.pace.paceStabilityScore.rounded()),
            wpm: analysis.pace.wordsPerMinute,
            pauseControl: Int(analysis.pauses.pauseControlScore.rounded()),
            pitchVariation: pitchConfidence >= 0.35
                ? Int(analysis.pitch.pitchVariationScore.rounded())
                : nil,
            pitchConfidence: pitchConfidence,
            recognizedWordCount: wordTimings.count,
            duration: elapsedTime,
            audioURL: recordingURL,
            date: Date()
        )
        liveWordsPerMinute = review.wpm
        isAnalyzing = false
        return review
    }

    func abandon() {
        guard isRecording || isAnalyzing else { return }
        isRecording = false
        isAnalyzing = false
        tearDownAudio()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
    }

    private func resetSession() {
        transcript = ""
        shouldFinishSession = false
        elapsedTime = 0
        liveWordsPerMinute = 0
        wordTimings = []
        silenceDurations = []
        isSilent = true
        hasDetectedSpeech = false
        silenceStartedAt = nil
        noiseFloorSamples = []
        noiseFloor = -55
        smoothedLevel = -60
        speechFrameCount = 0
        silenceFrameCount = 0
        alignmentEngine.configure(lines: renderedLines)
        activeLineIndex = 0
        driftState = .aligned
    }

    private func processTranscription(_ transcription: SFTranscription) {
        transcript = transcription.formattedString
        wordTimings = Self.timings(from: transcription)
        alignmentEngine.processTranscript(transcript, at: elapsedTime)
        activeLineIndex = alignmentEngine.state.activeLineIndex
        driftState = alignmentEngine.state.driftState
        updateLiveWordsPerMinute()
    }

    private func processAudioLevel(_ level: Float) {
        guard isRecording else { return }
        smoothedLevel = smoothedLevel * 0.82 + level * 0.18

        // Learn from the quieter frames instead of assuming the user stays silent
        // during a fixed calibration period.
        if isSilent || smoothedLevel < noiseFloor + 6 {
            noiseFloorSamples.append(smoothedLevel)
            if noiseFloorSamples.count > 180 {
                noiseFloorSamples.removeFirst(noiseFloorSamples.count - 180)
            }
            if noiseFloorSamples.count >= 12 {
                let sorted = noiseFloorSamples.sorted()
                let lowPercentileIndex = Int(Double(sorted.count - 1) * 0.3)
                let observedFloor = sorted[lowPercentileIndex]
                noiseFloor = noiseFloor * 0.92 + observedFloor * 0.08
                noiseFloor = min(-28, max(-65, noiseFloor))
            }
        }

        let now = Date()
        let speechOnThreshold = min(-24, noiseFloor + 10)
        let speechOffThreshold = min(-30, noiseFloor + 5)

        if isSilent {
            if smoothedLevel >= speechOnThreshold {
                speechFrameCount += 1
            } else {
                speechFrameCount = 0
            }

            // Require several consecutive loud frames so a chair scrape or door
            // click is not treated as the speaker resuming.
            guard speechFrameCount >= 3 else { return }
            speechFrameCount = 0
            silenceFrameCount = 0

            if hasDetectedSpeech, let silenceStartedAt {
                let duration = now.timeIntervalSince(silenceStartedAt)
                if duration >= 0.28 {
                    silenceDurations.append(duration)
                }
            }
            isSilent = false
            hasDetectedSpeech = true
            silenceStartedAt = nil
        } else {
            if smoothedLevel <= speechOffThreshold {
                silenceFrameCount += 1
            } else {
                silenceFrameCount = 0
            }

            // A slightly longer release avoids splitting words when consonants
            // briefly fall below the room's noise floor.
            if silenceFrameCount >= 5 {
                silenceFrameCount = 0
                speechFrameCount = 0
                isSilent = true
                silenceStartedAt = now
            }
        }
    }

    private func updateLiveWordsPerMinute() {
        guard let first = wordTimings.first, let last = wordTimings.last else {
            liveWordsPerMinute = 0
            return
        }
        let duration = max(1, last.endTime - first.startTime)
        liveWordsPerMinute = Int(round(Double(wordTimings.count) / (duration / 60)))
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedTime = Date().timeIntervalSince(startedAt)
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tearDownAudio() {
        timer?.invalidate()
        timer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioWriter = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        #if os(iOS)
        let microphoneAuthorized = await AVAudioApplication.requestRecordPermission()
        #else
        let microphoneAuthorized = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
        return speechAuthorized && microphoneAuthorized
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("practice-\(UUID().uuidString).caf")
    }

    private func contextualPhrases() -> [String] {
        let linePhrases = renderedLines.map(\.displayText)
        let anchorPhrases = renderedLines.flatMap { line -> [String] in
            let words = line.displayText.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count > 5 else { return [] }
            return stride(from: 0, to: words.count, by: 4).compactMap { start in
                let end = min(start + 5, words.count)
                guard end - start >= 3 else { return nil }
                return words[start..<end].joined(separator: " ")
            }
        }
        return Array((linePhrases + anchorPhrases).prefix(100))
    }

    nonisolated private static func decibels(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?.pointee else { return -120 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return -120 }
        var sum: Float = 0
        vDSP_measqv(channel, 1, &sum, vDSP_Length(count))
        let rms = sqrtf(sum)
        return 20 * log10f(max(rms, 0.000_001))
    }

    private static func timings(from transcription: SFTranscription) -> [RecognizedWordTiming] {
        transcription.segments.flatMap { segment -> [RecognizedWordTiming] in
            let words = ScriptRenderService.normalizeTokens(
                segment.substring,
                droppingFillers: false
            )
            guard !words.isEmpty else { return [] }
            let totalDuration = max(segment.duration, Double(words.count) * 0.12)
            let wordDuration = totalDuration / Double(words.count)
            return words.enumerated().map { index, word in
                RecognizedWordTiming(
                    word: word,
                    startTime: segment.timestamp + Double(index) * wordDuration,
                    duration: wordDuration
                )
            }
        }
    }
}

private enum PracticeSessionError: LocalizedError {
    case audioInputUnavailable
    case speechRecognitionUnavailable

    var errorDescription: String? {
        switch self {
        case .audioInputUnavailable:
            return "No microphone input is available."
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available for the current language."
        }
    }
}
