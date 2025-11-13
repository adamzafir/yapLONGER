import SwiftUI
import AVFoundation

struct Screen5: View {
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var progressTimer: Timer?
    @State private var isScrubbing = false
    @Binding var scoreTwo: Double
    
    // Gauge progress (0.0 ... 1.0)
    @State private var gaugeProgress: Double = 0.67

    private func configureAudioSessionForPlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed:", error)
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let player = audioPlayer, !isScrubbing else { return }
            currentTime = player.currentTime
            if !player.isPlaying || currentTime >= duration {
                progressTimer?.invalidate()
                progressTimer = nil
            }
        }
    }

    func playSound(sound: String, type: String) {
        configureAudioSessionForPlayback()

        guard let url = Bundle.main.url(forResource: sound, withExtension: type) else {
            print("Audio file not found:", sound, ".", type)
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            startProgressTimer()
        } catch {
            print("AVAudioPlayer init error:", error)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Gauge
                SemiCircleGauge(progress: max(0.0, min(1.0, scoreTwo / 100.0)))
                    .frame(height: 160)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // Progress slider & timestamps
                VStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { duration > 0 ? currentTime : 0 },
                        set: { newValue in
                            currentTime = min(max(0, newValue), duration)
                        }
                    ), in: 0...max(duration, 0.001), onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing, let player = audioPlayer {
                            player.currentTime = currentTime
                            if !player.isPlaying { player.play() }
                            startProgressTimer()
                        }
                    })
                    .padding(.horizontal)

                    HStack {
                        Text(formatTime(currentTime))
                        Spacer()
                        Text(formatTime(duration))
                    }
                    .font(.caption)
                    .monospacedDigit()
                }

                // Playback controls
                HStack(spacing: 24) {
                    // Back 15s
                    Button {
                        let newTime = max(0, currentTime - 15)
                        currentTime = newTime
                        audioPlayer?.currentTime = newTime
                    } label: {
                        Label("Back 15s", systemImage: "gobackward.15")
                    }

                    // Play/Pause
                    Button {
                        configureAudioSessionForPlayback()

                        guard let player = audioPlayer else {
                            currentTime = 0
                            playSound(sound: "cooked-dog-meme", type: "mp3")
                            return
                        }

                        if player.isPlaying {
                            player.pause()
                            progressTimer?.invalidate()
                            progressTimer = nil
                        } else {
                            player.currentTime = currentTime
                            player.play()
                            startProgressTimer()
                        }
                    } label: {
                        let isPlaying = audioPlayer?.isPlaying == true
                        Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                            .font(.headline)
                    }

                    // Forward 15s
                    Button {
                        let newTime = min(duration, currentTime + 15)
                        currentTime = newTime
                        audioPlayer?.currentTime = newTime
                    } label: {
                        Label("Forward 15s", systemImage: "goforward.15")
                    }
                }
            }
            .padding()
            .navigationTitle("Review")
            .onAppear {
                configureAudioSessionForPlayback()
            }
            .onDisappear {
                progressTimer?.invalidate()
                progressTimer = nil
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite && !t.isNaN else { return "0:00" }
        let total = Int(t.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension Screen5 {
    struct SemiCircleGauge: View {
        var progress: Double
        var lineWidth: CGFloat = 16

        var body: some View {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                ZStack {
                    Arc(startAngle: .degrees(180), endAngle: .degrees(360))
                        .stroke(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                    Arc(startAngle: .degrees(180), endAngle: .degrees(180 + 180 * progress))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .animation(.easeInOut(duration: 0.4), value: progress)

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                        .offset(y: size * 0.15)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    struct Arc: Shape {
        var startAngle: Angle
        var endAngle: Angle

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let radius = min(rect.width, rect.height)
            let center = CGPoint(x: rect.midX, y: rect.maxY)
            path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            return path
        }
    }
}

#Preview {
    Screen5(scoreTwo: .constant(67))
}
