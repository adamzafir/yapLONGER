import SwiftUI
import AVFoundation
import Speech

func splitIntoLinesByWidth(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
    let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    var lines: [String] = []
    var currentLine = ""

    for word in words {
        let testLine = currentLine.isEmpty ? word : "\(currentLine) \(word)"
        let size = (testLine as NSString).size(withAttributes: [.font: font])
        
        if size.width <= maxWidth {
            currentLine = testLine
        } else {
            if !currentLine.isEmpty {
                lines.append(currentLine)
            }
            currentLine = word
        }
    }
    
    if !currentLine.isEmpty {
        lines.append(currentLine)
    }
    
    return lines
}

struct Screen3Teleprompter: View {
    @State private var showAccessory = false
    let synthesiser = AVSpeechSynthesizer()
    let audioEngine = AVAudioEngine()
    let speechRecogniser = SFSpeechRecognizer(locale: .current)
    @State var transcription = ""
    @State var isRecording = false
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    @Binding var script: String
    @State var scriptLines: [String] = []
    @State private var isLoading = true
    @AppStorage("fontSize") var fontSize: Double = 28

    private func recomputeLines() {
        let font = UIFont.systemFont(ofSize: CGFloat(fontSize))
        let maxWidth = UIScreen.main.bounds.width - 32
        scriptLines = splitIntoLinesByWidth(script, font: font, maxWidth: maxWidth)
    }

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(scriptLines, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: CGFloat(fontSize)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()

                HStack {
                    Button {
                        isRecording.toggle()
                        showAccessory.toggle()
                    } label: {
                        RecordButtonView(isRecording: $isRecording)
                    }
                    .sensoryFeedback(.selection, trigger: showAccessory)
                }

                Text(transcription.isEmpty ? "..." : transcription)
            }
            .onAppear {
                Task {
                    recomputeLines()
                    isLoading = false
                }
            }
            .onChange(of: fontSize) { _ in
                recomputeLines()
            }
            .onChange(of: script) { _ in
                recomputeLines()
            }
            .navigationTitle(title)
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
            }
            .onChange(of: isRecording) { recording in
                if recording {
                    SFSpeechRecognizer.requestAuthorization { status in
                        guard status == .authorized else { return }
                    }

                    Task {
                        let micGranted = await AVAudioApplication.requestRecordPermission()
                        guard micGranted else { return }
                    }

                    guard let recogniser = speechRecogniser, recogniser.isAvailable else { return }

                    let audioSession = AVAudioSession.sharedInstance()
                    try? audioSession.setCategory(.record, mode: .measurement)
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
                    audioEngine.stop()
                    audioEngine.inputNode.removeTap(onBus: 0)
                }
            }
        }
    }
}

#Preview {
    Screen3Teleprompter(
        title: .constant("The Impact of Social Media on Society"),
        script: .constant("Social media has profoundly transformed the way people communicate and interact with one another. Over the past decade, platforms like Facebook, Twitter, and Instagram have enabled instant sharing of information, connecting people across the globe. On the positive side, social media allows for real-time communication, collaboration, and access to educational resources. Social movements have gained traction through social media campaigns, giving a voice to marginalized communities. However, there are also significant drawbacks. The constant exposure to curated content can lead to unrealistic expectations, mental health issues, and the spread of misinformation. Social media algorithms often prioritize engagement over accuracy, amplifying sensationalized content. In addition, the addictive nature of these platforms can disrupt daily routines and productivity. It is essential for individuals to practice mindful consumption, critically evaluate content, and maintain a healthy balance between online and offline interactions to mitigate the negative effects of social media while still leveraging its potential for connectivity and learning.")
    )
}
