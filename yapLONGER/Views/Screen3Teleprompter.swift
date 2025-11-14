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

private func normalizeAndTokenize(_ text: String) -> [String] {
    let lowered = text.lowercased()
    let stripped = lowered.unicodeScalars.map { CharacterSet.punctuationCharacters.contains($0) ? " " : String($0) }.joined()
    return stripped
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
}

private func isSubsequence(_ small: [String], in big: [String]) -> Bool {
    guard !small.isEmpty else { return true }
    var i = 0
    for token in big {
        if token == small[i] {
            i += 1
            if i == small.count { return true }
        }
    }
    return false
}

struct Screen3Teleprompter: View {
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
    @State var scriptLines: [String] = []
    @State private var isLoading = true
    @AppStorage("fontSize") var fontSize: Double = 28
    @State private var tokensPerLine: [[String]] = []
    @State private var currentLineIndex: Int = 0
    @State private var lastAdvanceTime: Date = .distantPast

    private func recomputeLines() {
        let font = UIFont.systemFont(ofSize: CGFloat(fontSize))
        let maxWidth = UIScreen.main.bounds.width - 32
        scriptLines = splitIntoLinesByWidth(script, font: font, maxWidth: maxWidth)
        tokensPerLine = scriptLines.map { normalizeAndTokenize($0) }
        currentLineIndex = min(currentLineIndex, max(0, scriptLines.count - 1))
    }

    private func tryAdvance(using recognizedTokens: [String], scrollProxy: ScrollViewProxy) {
        guard currentLineIndex < tokensPerLine.count else { return }
        let now = Date()
        if now.timeIntervalSince(lastAdvanceTime) < 0.3 { return }

        let expected = tokensPerLine[currentLineIndex]
        if expected.isEmpty || isSubsequence(expected, in: recognizedTokens) {
            let nextIndex = currentLineIndex + 1
            if nextIndex <= scriptLines.count {
                currentLineIndex = min(nextIndex, scriptLines.count - 1)
                lastAdvanceTime = now

                withAnimation(.easeInOut) {
                    scrollProxy.scrollTo(currentLineIndex, anchor: .top)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(scriptLines.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(size: CGFloat(fontSize)))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                        .background(index == currentLineIndex ? Color.primary.opacity(0.08) : Color.clear)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: currentLineIndex) { _, newValue in
                            withAnimation(.easeInOut) {
                                proxy.scrollTo(newValue, anchor: .top)
                            }
                        }
                        .onAppear {
                            if !scriptLines.isEmpty {
                                proxy.scrollTo(0, anchor: .top)
                            }
                        }
                        .onChange(of: transcription) { _, newValue in
                            let tokens = normalizeAndTokenize(newValue)
                            tryAdvance(using: tokens, scrollProxy: proxy)
                        }
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
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .onAppear {
                Task {
                    recomputeLines()
                    isLoading = false
                }
            }
            .onChange(of: fontSize) { _, _ in
                recomputeLines()
            }
            .onChange(of: script) { _, _ in
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
            .onChange(of: isRecording) { _, recording in
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
    .environmentObject(RecordingStore())
}
