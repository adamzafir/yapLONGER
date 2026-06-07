import SwiftUI
import AVFoundation
import Speech
import FoundationModels

@Generable
struct keyword {
    @Guide(description: "Key Words/Phrases from the script")
    var keywords: [String]
}

struct Screen3Keywords: View {
    @EnvironmentObject private var recordingStore: RecordingStore
    
    @State private var showAccessory = false
    let synthesiser = AVSpeechSynthesizer()
    let audioEngine = AVAudioEngine()
    let speechRecogniser = SFSpeechRecognizer(locale: .current)
    @State var transcription = ""
    @State var isRecording = false
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    @Binding var script: String
    let session = LanguageModelSession()
    @State var response2: keyword = .init(keywords: [])
    @State var response3: [String] = []
    
    // Add states needed by Screen4
    @State private var LGBW: Int = 0
    @State private var elapsedTime: Int = 0
    @State private var wordCount: Int = 0
    
    @State private var isLoading = true
    @State private var navigateToScreen4 = false

    // Speech recognition lifecycle
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    
    var body: some View {
        NavigationStack {
           
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    Spacer()
                    ZStack {
                        VStack(spacing: 8) {
                            ProgressView("Loading...")
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding(.bottom, 4)
                            Text("Powered By")
                                .fontWeight(.medium)
                                .font(.title3)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Text("Avyan Intelligence")
                                .font(.system(size: 35, weight: .semibold))
                                .appleIntelligenceGradient()
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.horizontal, 16)
                        VStack {
                            Spacer()
                            GlowEffect()
                                .offset(y: 25)
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Keywords:")
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            ForEach(response3, id: \.self) { word in
                                Text(word)
                                    .font(.title2.bold())
                                    .padding(5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                
                Spacer(minLength: 8)
                
                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        Button {
                            let newValue = !isRecording
                            isRecording = newValue
                            showAccessory.toggle()
                            if newValue {
                                // Start
                                recordingStore.startRecording()
                                SFSpeechRecognizer.requestAuthorization { _ in }
                                #if os(iOS)
                                Task { _ = await AVAudioApplication.requestRecordPermission() }
                                #elseif os(macOS)
                                AVCaptureDevice.requestAccess(for: .audio) { _ in }
                                #endif
                                guard let recogniser = speechRecogniser, recogniser.isAvailable else { return }
                                
                                #if os(iOS)
                                let audioSession = AVAudioSession.sharedInstance()
                                try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                                try? audioSession.setActive(true)
                                #endif
                                
                                let request = SFSpeechAudioBufferRecognitionRequest()
                                request.shouldReportPartialResults = true
                                recognitionRequest = request
                                
                                let inputNode = audioEngine.inputNode
                                let format = inputNode.outputFormat(forBus: 0)
                                
                                inputNode.removeTap(onBus: 0)
                                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                                    request.append(buffer)
                                }
                                audioEngine.prepare()
                                try? audioEngine.start()
                                
                                recognitionTask = recogniser.recognitionTask(with: request) { result, error in
                                    if let result {
                                        transcription = result.bestTranscription.formattedString
                                    }
                                    if error != nil {
                                        stopSpeechRecognition()
                                    }
                                }
                            } else {
                                // Stop
                                recordingStore.stopRecording()
                                stopSpeechRecognition()
                                navigateToScreen4 = true
                            }
                        } label: {
                            RecordButtonView(isRecording: $isRecording)
                        }
                        .sensoryFeedback(.selection, trigger: showAccessory)
                        
                        Text(transcription)
                            .font(.body)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
            .navigationTitle($title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
                #else
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
                #endif
            }
            .onAppear {
                Task {
                    let prompt = "Reply with only the keywords/phrases, each on a new line from: \(script)"
                    let response = try await session.respond(to: prompt, generating: keyword.self)
                    response2 = response.content
                    response3 = response2.keywords
                    isLoading = false
                }
            }
        }
    }

    private func stopSpeechRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}

#Preview {
    Screen3Keywords(
        title: .constant("The Impact of Social Media on Society"),
        script: .constant("Social media has profoundly transformed the way people communicate and interact with one another. Over the past decade, platforms like Facebook, Twitter, and Instagram have enabled instant sharing of information, connecting people across the globe. On the positive side, social media allows for real-time communication, collaboration, and access to educational resources. Social movements have gained traction through social media campaigns, giving a voice to marginalized communities. However, there are also significant drawbacks. The constant exposure to curated content can lead to unrealistic expectations, mental health issues, and the spread of misinformation. Social media algorithms often prioritize engagement over accuracy, amplifying sensationalized content. In addition, the addictive nature of these platforms can disrupt daily routines and productivity. It is essential for individuals to practice mindful consumption, critically evaluate content, and maintain a healthy balance between online and offline interactions to mitigate the negative effects of social media while still leveraging its potential for connectivity and learning.")
    )
    .environmentObject(RecordingStore())
}
