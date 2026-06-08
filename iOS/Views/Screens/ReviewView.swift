import SwiftUI
import AVFoundation

struct ReviewView: View {
    // Target script to append review to
    var scriptItemID: UUID? = nil
    // Optional callback for external save handling (e.g., watch->phone)
    var onSave: ((Review) -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var showsSaveButton: Bool = true
    var autoPersistOnAppear: Bool = false

    @EnvironmentObject private var scriptsViewModel: Screen2ViewModel
    @Environment(\.dismiss) private var dismiss

    @Binding private var review: Review

    // MARK: - Audio playback state
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackTimer: Timer?
    @State private var hasPersisted = false

    // MARK: - Expansions
    @State private var expandWPM = false
    @State private var expandCIS = false
    @State private var expandPauses = false
    @State private var expandPitch = false

    init(review: Binding<Review>, scriptItemID: UUID? = nil, showsSaveButton: Bool = true, autoPersistOnAppear: Bool = false, onSave: ((Review) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        _review = review
        self.scriptItemID = scriptItemID
        self.showsSaveButton = showsSaveButton
        self.autoPersistOnAppear = autoPersistOnAppear
        self.onSave = onSave
        self.onDismiss = onDismiss
    }

    init(review: Review, scriptItemID: UUID? = nil, showsSaveButton: Bool = false, autoPersistOnAppear: Bool = false, onSave: ((Review) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        _review = .constant(review)
        self.scriptItemID = scriptItemID
        self.showsSaveButton = showsSaveButton
        self.autoPersistOnAppear = autoPersistOnAppear
        self.onSave = onSave
        self.onDismiss = onDismiss
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: review.date)
    }

    private var pitchGrade: String {
        guard let score = review.pitchVariation else { return "Not enough audio" }
        switch score {
        case 80...: return "Expressive"
        case 60..<80: return "Balanced"
        case 40..<60: return "Developing"
        default: return "Too flat"
        }
    }

    private var sessionDetail: String? {
        guard let wordCount = review.recognizedWordCount, let duration = review.duration else {
            return nil
        }
        let totalSeconds = Int(duration.rounded())
        return "\(wordCount) words recognized in \(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private func togglePlayback() {
        guard let url = review.resolvedAudioURL else { return }

        if let player = audioPlayer, player.url == url {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                stopPlaybackTimer()
            } else {
                player.play()
                isPlaying = true
                startPlaybackTimer()
            }
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            player.play()
            isPlaying = true
            startPlaybackTimer()
        } catch {
            print("Audio playback error: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    private func persistReview(shouldDismiss: Bool = true) {
        guard !hasPersisted else {
            if shouldDismiss {
                dismiss()
                onDismiss?()
            }
            return
        }

        if let sid = scriptItemID {
            scriptsViewModel.appendReview(review, to: sid)
        }
        onSave?(review)
        hasPersisted = true
        InteractionFeedback.success()
        if shouldDismiss {
            dismiss()
            onDismiss?()
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Practice complete")
                            .font(.title3.weight(.semibold))
                        Text(formattedDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let sessionDetail {
                            Text(sessionDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if review.resolvedAudioURL != nil {
                        Button {
                            togglePlayback()
                        } label: {
                            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                                .foregroundStyle(.pri)
                        }
                        .tint(.pri)
                        .buttonStyle(.bordered)
                        .accessibilityLabel(isPlaying ? "Pause recording" : "Play recording")
                    }
                }
            }

            Section("Delivery") {
                DisclosureGroup(isExpanded: $expandWPM) {
                    SemiCircleGauge(
                        progress: max(0, min(1, Double(review.wpm)/220)),
                        highlight: (100.0/220)...(140.0/220),
                        minLabel: "0",
                        maxLabel: "220",
                        valueLabel: "\(review.wpm)"
                    )
                    .frame(height: 110)

                    Text(wpmFeedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } label: {
                    HStack {
                        Text("Words Per Minute")
                        Spacer()
                        Text("\(review.wpm)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup(isExpanded: $expandCIS) {
                    HStack {
                        SemiCircleGauge(
                            progress: max(0,min(1,Double(review.cis)/100)),
                            highlight: (75.0/100)...(85.0/100),
                            minLabel: "0%",
                            maxLabel: "100%",
                            valueLabel: "\(review.cis)%"
                        )
                        .frame(height: 110)
                    }
                    Text(paceFeedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } label: {
                    HStack {
                        Text("Pace Consistency")
                        Spacer()
                        Text("\(review.cis)%").monospacedDigit().foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup(isExpanded: $expandPauses) {
                    SemiCircleGauge(
                        progress: max(0, min(1, Double(review.pauseControl) / 100)),
                        highlight: 0.75...1,
                        minLabel: "0%",
                        maxLabel: "100%",
                        valueLabel: "\(review.pauseControl)%"
                    )
                    .frame(height: 110)

                    Text(review.pauseControl >= 75
                         ? "Your pauses were controlled and generally well placed."
                         : "Try replacing hesitant gaps with shorter, intentional pauses.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } label: {
                    HStack {
                        Text("Pause Control")
                        Spacer()
                        Text("\(review.pauseControl)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup(isExpanded: $expandPitch) {
                    if let pitch = review.pitchVariation {
                        SemiCircleGauge(
                            progress: max(0, min(1, Double(pitch) / 100)),
                            highlight: 0.65...0.9,
                            minLabel: "Flat",
                            maxLabel: "Varied",
                            valueLabel: "\(pitch)%"
                        )
                        .frame(height: 110)

                        Text(pitchFeedback)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView {
                            Label("Pitch unavailable", systemImage: "waveform.slash")
                        } description: {
                            Text("Speak for a little longer and keep the microphone close enough for a clean pitch reading.")
                        }
                    }
                } label: {
                    HStack {
                        Text("Pitch Variation")
                        Spacer()
                        Text(pitchGrade)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if showsSaveButton {
                Button {
                    persistReview()
                } label: {
                    Text(hasPersisted ? "Done" : "Save Review")
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.pri)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Review")
        .onAppear {
            if autoPersistOnAppear {
                persistReview(shouldDismiss: false)
            }
        }
        .onDisappear {
            audioPlayer?.stop()
            isPlaying = false
            stopPlaybackTimer()
        }
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            guard let player = audioPlayer, !player.isPlaying else { return }
            isPlaying = false
            stopPlaybackTimer()
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private var wpmFeedback: String {
        if review.wpm < 100 {
            return "Your pace was measured from recognized words. Try moving slightly faster while keeping clear articulation."
        }
        if review.wpm > 140 {
            return "Your pace may be difficult to follow. Add breathing room around important ideas."
        }
        return "Your overall speaking speed was in a clear presentation range."
    }

    private var paceFeedback: String {
        if review.cis >= 80 {
            return "Your speaking speed stayed steady across the practice."
        }
        if review.cis >= 60 {
            return "Your pace shifted between sections. Rehearse transitions to make the changes feel intentional."
        }
        return "Your speed changed significantly during the practice. Aim for a steadier rhythm before adding dramatic pace changes."
    }

    private var pitchFeedback: String {
        guard let pitch = review.pitchVariation else { return "" }
        if pitch >= 80 {
            return "Strong vocal variety. Your pitch moved enough to create emphasis without becoming erratic."
        }
        if pitch >= 60 {
            return "Your pitch had useful variation. Push key words a little further to make the structure clearer."
        }
        if pitch >= 40 {
            return "Some pitch movement was detected, but longer sections stayed fairly level."
        }
        return "Your delivery was mostly flat. Mark a few key phrases to lift, lower, or stress."
    }
}

// MARK: - Gauge
struct SemiCircleGauge: View {
    var progress: Double
    var lineWidth: CGFloat = 14
    var label: String? = nil
    var highlight: ClosedRange<Double>?
    var minLabel: String?
    var maxLabel: String?
    var valueLabel: String?
    
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let thick = max(10, min(14, h*2))
            let x = max(0,min(1,progress))*w
            let high = highlight.map { r -> (CGFloat,CGFloat) in
                let s = CGFloat(r.lowerBound)*w
                let e = CGFloat(r.upperBound)*w
                return (s,e-s)
            }
            
            ZStack {
                if let hframe = high {
                    Capsule()
                        .fill(Color.green.opacity(0.25))
                        .frame(width:hframe.1,height:thick)
                        .position(x:hframe.0+hframe.1/2,y:h/2)
                }
                
                Capsule()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width:w,height:thick)
                    .position(x:w/2,y:h/2)
                
                Capsule()
                    .fill(progress>=0.5 ? Color.blue : Color.orange)
                    .frame(width:3,height:max(thick,20))
                    .position(x:x,y:h/2)
                
                if let min = minLabel {
                    Text(min).font(.caption2).position(x:10,y:h/2+thick/2+12)
                }
                if let max = maxLabel {
                    Text(max).font(.caption2).position(x:w-10,y:h/2+thick/2+12)
                }
                
                if let v = valueLabel {
                    Text(v).font(.caption).position(x:min(max(12,x),w-12),y:h/2-thick/2-10)
                }
            }
        }
    }
}

#Preview {
    ReviewView(
        review: Review(cis: 72, wpm: 118, audioURL: nil, date: Date()),
        scriptItemID: UUID(),
        showsSaveButton: true
    )
    .environmentObject(Screen2ViewModel())
}
