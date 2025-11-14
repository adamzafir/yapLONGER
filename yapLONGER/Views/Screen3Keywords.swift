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
    
    @State private var isLoading = true
    @State private var navigateToScreen4 = false
    
    var body: some View {
        NavigationStack {
            NavigationLink(destination: Screen4(LGBW: .constant(0), elapsedTime: .constant(0), wordCount:.constant(0) ), isActive: $navigateToScreen4) { EmptyView() }
            VStack(spacing: 20) {
                if isLoading {
                    Spacer()
                    ZStack {
                        VStack(spacing: 4) {
                            ProgressView("Loading...")
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding()
                            Text("Powered By")
                                .fontWeight(.medium)
                                .font(.title3)
                            Text("Avyan Intelligence")
                                .font(.system(size: 35, weight: .semibold))
                                .appleIntelligenceGradient()
                        }
                        VStack {
                            Spacer()
                            GlowEffect()
                                .offset(y: 25)
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            Text("Keywords:")
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity, alignment: .center)
                            
                            ForEach(response3, id: \.self) { word in
                                Text(word)
                                    .font(.title2.bold())
                                    .padding(5)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding()
                    }
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    HStack {
                        Button {
                            isRecording.toggle()
                            showAccessory.toggle()
                        } label: {
                            RecordButtonView(isRecording: $isRecording)
                        }
                        .sensoryFeedback(.selection, trigger: showAccessory)
                        
                        Text(transcription)
                            .font(.body)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle($title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
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
            .onChange(of: isRecording) { recording in
                if recording {
                    // Start file recording
                    recordingStore.startRecording()
                    
                    // Start speech recognition
                    SFSpeechRecognizer.requestAuthorization { status in
                        guard status == .authorized else { return }
                    }
                    Task {
                        let micGranted = await AVAudioApplication.requestRecordPermission()
                        guard micGranted else { return }
                    }
                    guard let recogniser = speechRecogniser, recogniser.isAvailable else { return }
                    
                    let audioSession = AVAudioSession.sharedInstance()
                    try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                    try? audioSession.setActive(true)
                    
                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true
                    
                    let inputNode = audioEngine.inputNode
                    let format = inputNode.outputFormat(forBus: 0)
                    
                    inputNode.removeTap(onBus: 0)
                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                        request.append(buffer)
                    }
                    audioEngine.prepare()
                    try? audioEngine.start()
                    
                    recogniser.recognitionTask(with: request) { result, _ in
                        if let result {
                            transcription = result.bestTranscription.formattedString
                        }
                    }
                } else {
                    // Stop both
                    recordingStore.stopRecording()
                    audioEngine.stop()
                    audioEngine.inputNode.removeTap(onBus: 0)
                    navigateToScreen4 = true
                }
            }
        }
    }
}

#Preview {
    Screen3Keywords(
        title: .constant("The Impact of Social Media on Society"),
        script: .constant("Social media has profoundly transformed the way people communicate and interact with one another. Over the past decade, platforms like Facebook, Twitter, and Instagram have enabled instant sharing of information, connecting people across the globe. On the positive side, social media allows for real-time communication, collaboration, and access to educational resources. Social movements have gained traction through social media campaigns, giving a voice to marginalized communities. However, there are also significant drawbacks. The constant exposure to curated content can lead to unrealistic expectations, mental health issues, and the spread of misinformation. Social media algorithms often prioritize engagement over accuracy, amplifying sensationalized content. In addition, the addictive nature of these platforms can disrupt daily routines and productivity. It is essential for individuals to practice mindful consumption, critically evaluate content, and maintain a healthy balance between online and offline interactions to mitigate the negative effects of social media while still leveraging its potential for connectivity and learning.")
    )
    .environmentObject(RecordingStore())
}
