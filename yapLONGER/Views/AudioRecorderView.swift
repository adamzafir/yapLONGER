//
//  AudioRecorderView.swift
//  yapLONGER
//
//  Created by T Krobot on 13/11/25.
//

import SwiftUI
import AVKit

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
    
    var body: some View {
        NavigationView {
            VStack {
                NavigationLink(
                    destination: Screen5(recordingURL: latestRecordingURL, scoreTwo: $scoreTwo),
                    isActive: $navigateToScreen5
                ) { EmptyView() }
                
                Button(action: {
                    if record {
                        // Stop recording
                        recorder?.stop()
                        record = false
                        // Capture the just-recorded URL and navigate to Screen 5
                        latestRecordingURL = currentRecordingURL
                        recorder = nil
                        getAudios()
                        if latestRecordingURL != nil {
                            navigateToScreen5 = true
                        }
                    } else {
                        startRecording()
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
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
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
}

#Preview {
    AudioRecorderView()
}
