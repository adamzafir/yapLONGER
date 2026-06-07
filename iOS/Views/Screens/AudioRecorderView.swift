//
//  AudioRecorderView.swift
//  yapLONGER
//
//  Created by T Krobot on 13/11/25.
//

import SwiftUI
import AVKit

#if os(iOS)
struct AudioRecorderView: View {
    @State private var record = false
    @State private var session: AVAudioSession?
    @State private var recorder: AVAudioRecorder?
    @State private var alert = false
    @State private var audio = false
    @State private var audios: [URL] = []
    @State private var currentRecordingURL: URL?
    @State private var latestRecordingURL: URL?
    @State private var navigateToScreen5 = false
    @State private var scoreTwo: Double = 0
    @State private var currentDate = Date.now
    @State var elapsedTime: Int = 0
    @State private var timer: Timer? = nil

    // Silence detection state
    @State private var meteringTimer: Timer? = nil
    @State private var isCurrentlySilent: Bool = true
    @State private var lastSpeechEndTime: Date? = nil
    @State private var lastSilenceStartTime: Date? = nil
    @State private var silenceDurations: [TimeInterval] = []
    @State var LGBW: TimeInterval = 0 // largest gap between words (seconds)

    // Tuning parameters
    private let silenceThreshold: Float = -40.0 // dB level regarded as silence (lower is quieter)
    private let minSilenceDuration: TimeInterval = 0.25 // ignore very short blips
    private let meteringInterval: TimeInterval = 0.05 // 20 Hz sampling

    
    @State private var showingAlert = false
    var formattedTime: String {
        let minutes = elapsedTime / 60
        let seconds = elapsedTime % 60
        return String(format: "%02d:%02d", minutes, seconds)
        
    }

    var body: some View {
        NavigationView {
            VStack {
                NavigationLink(
                    destination: Screen5(recordingURL: latestRecordingURL),
                    isActive: $navigateToScreen5
                ) { EmptyView() }
                
                Button(action: {
                    if record {
                        // Stop recording
                        recorder?.stop()
                        stopMetering()
                        finalizeSilenceIfNeeded()
                        record = false
                        // Capture the just-recorded URL and navigate to Screen 5
                        latestRecordingURL = currentRecordingURL
                        recorder = nil
                        resetSilenceTracking()
                        getAudios()
                        if latestRecordingURL != nil {
                            navigateToScreen5 = true
                        }
                    } else {
                        startRecording()
                        elapsedTime = 0
                        timer?.invalidate()
                        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                            elapsedTime += 1
                            
                        }
                        startMetering()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 70, height: 70)
                        if self.record {
                            Circle()
                                .stroke(Color.white, lineWidth: 6)
                                .frame(width: 85, height: 85)
                        }
                    }
                }
                .padding(.vertical, 25)
            }
            .navigationBarTitle("RecordAudio")
        }
        .alert(isPresented: self.$alert, content: {
            Alert(title: Text("Error"), message: Text("Enable Microphone Access in Settings"))
        })
        .onAppear {
            configureAudioSessionAndRequestPermission()
        }
    }
    
    private func configureAudioSessionAndRequestPermission() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            self.session = session
            
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if !granted {
                            self.alert = true
                        } else {
                            self.getAudios()
                        }
                    }
                }
            } else {
                session.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if !granted {
                            self.alert = true
                        } else {
                            self.getAudios()
                        }
                    }
                }
            }
        } catch {
            print("Audio session error: \(error.localizedDescription)")
        }
    }
    
    private func startRecording() {
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = docs.appendingPathComponent("myRcd\(self.audios.count + 1).m4a")
            self.currentRecordingURL = fileName
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let newRecorder = try AVAudioRecorder(url: fileName, settings: settings)
            newRecorder.isMeteringEnabled = true
            newRecorder.prepareToRecord()
            newRecorder.record()
            self.recorder = newRecorder
            self.record = true
        } catch {
            print("Start recording error: \(error.localizedDescription)")
        }
    }
    
    private func getAudios() {
        do {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let result = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            self.audios = result
                .filter { $0.pathExtension.lowercased() == "m4a" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("List audios error: \(error.localizedDescription)")
        }
    }
    
    private func startMetering() {
        meteringTimer?.invalidate()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: meteringInterval, repeats: true) { _ in
            guard let recorder = recorder else { return }
            recorder.updateMeters()
            // Using average power on channel 0
            let level = recorder.averagePower(forChannel: 0)
            handleLevel(level)
        }
        RunLoop.current.add(meteringTimer!, forMode: .common)
       
        isCurrentlySilent = true
        lastSpeechEndTime = nil
        lastSilenceStartTime = Date()
    }

    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    private func handleLevel(_ level: Float) {
        let now = Date()
        if level <= silenceThreshold {
            //silence
            if !isCurrentlySilent {
                //if in silence
                isCurrentlySilent = true
                lastSpeechEndTime = now
                lastSilenceStartTime = now
            }
        } else {
            //speaking
            if isCurrentlySilent {
                // from silence to speaking
                isCurrentlySilent = false
                if let silenceStart = lastSilenceStartTime {
                    let duration = now.timeIntervalSince(silenceStart)
                    if duration >= minSilenceDuration {
                        silenceDurations.append(duration)
                        if duration > LGBW { LGBW = duration }
                    }
                }
                lastSilenceStartTime = nil
            }
        }
    }

    private func finalizeSilenceIfNeeded() {
        // If recording stopped during a silence cout it
        if isCurrentlySilent, let silenceStart = lastSilenceStartTime {
            let duration = Date().timeIntervalSince(silenceStart)
            if duration >= minSilenceDuration {
                silenceDurations.append(duration)
                if duration > LGBW { LGBW = duration }
            }
        }
    }

    private func resetSilenceTracking() {
        isCurrentlySilent = true
        lastSpeechEndTime = nil
        lastSilenceStartTime = nil
        silenceDurations.removeAll()
        LGBW = 0
    }
}

#Preview {
    AudioRecorderView()
}
#else
struct AudioRecorderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Audio Recording Unavailable", systemImage: "mic.slash")
        } description: {
            Text("Audio recording is only available on iOS.")
        }
    }
}
#endif
