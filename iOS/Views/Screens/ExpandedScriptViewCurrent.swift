import SwiftUI
import FoundationModels

struct Screen22: View {
    var scriptItemID: UUID

    @EnvironmentObject private var scriptsViewModel: Screen2ViewModel
    #if os(macOS)
    @EnvironmentObject private var macSessionState: MacSessionState
    #endif

    @Binding var title: String
    @Binding var script: String
    
    @FocusState private var isEditingScript: Bool
    @FocusState private var isEditingTitle: Bool
    
    @State private var showScreent = false
    @State private var WPM: Int = 120
    @State private var isLoading = false
    
    @State private var isTyping = false
    @State private var typingResetTask: Task<Void, Never>? = nil
    
    @State private var wordCount: Int = 0
    @State private var rewriting = false
    @State private var rewritePrompt = """
    Rewrite this script. Reply with ONLY the rewritten version of this script...
    """
    @State private var showPromptDialog = false
    @State private var rewriteError: String? = nil
    
    private func wrdEstimateString(for wordCount: Int, wpm: Int = 120) -> String {
        guard wordCount > 0, wpm > 0 else { return "0 min 0 sec" }
        let totalSeconds = Double(wordCount) / Double(wpm) * 60.0
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        if minutes == 0 {
            return "\(seconds) sec"
        } else if seconds == 0 {
            return "\(minutes) min"
        } else {
            return "\(minutes) min \(seconds) sec"
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
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
                    TextField("Untitled Script", text: $title)
                        .focused($isEditingTitle)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                    
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $script)
                            .focused($isEditingScript)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            #if os(macOS)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            #else
                            .background(Color.clear)
                            #endif
                            .onChange(of: script) { _, newValue in
                                wordCount = newValue.split { $0.isWhitespace }.count
                                
                                isTyping = true
                                typingResetTask?.cancel()
                                typingResetTask = Task {
                                    try? await Task.sleep(nanoseconds: 700_000_000)
                                    await MainActor.run { isTyping = false }
                                }
                            }
                        
                        if script.isEmpty && !isEditingScript {
                            Text("Write something inspiring...")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .onAppear {
                wordCount = script.split { $0.isWhitespace }.count
            }
            .alert("Rewrite Failed", isPresented: Binding(
                get: { rewriteError != nil },
                set: { if !$0 { rewriteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rewriteError ?? "Unknown error")
            }
            .confirmationDialog("Rewrite with AI", isPresented: $showPromptDialog, titleVisibility: .visible) {
                TextField("Prompt for rewriting", text: $rewritePrompt)
                
                Button("Rewrite Now") {
                    rewriting = true
                    isLoading = true
                    Task {
                        do {
                            let session = LanguageModelSession()
                            let result = try await session.respond(to: """
                            Rewrite this text using these instructions: \(rewritePrompt)
                            
                            Original:
                            \(script)
                            """)
                            script = result.content
                        } catch {
                            rewriteError = error.localizedDescription
                        }
                        rewriting = false
                        isLoading = false
                    }
                }.disabled(rewriting)
                
                Button("Cancel", role: .cancel) {}
            }
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button { showScreent = true } label: {
                        Image(systemName: "music.microphone")
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showPromptDialog = true
                        } label: {
                            Label("Rewrite with Apple Intelligence", systemImage: "wand.and.stars")
                        }

                        Button {
                            showScreent = true
                        } label: {
                            Label("Start Practice", systemImage: "mic.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        // Dismiss any active text input (title or script)
                        isEditingScript = false
                        isEditingTitle = false
                        // If you ever need an extra safety net:
                        // UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
                #endif
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isEditingScript && !isEditingTitle && !isTyping {
                VStack(spacing: 10) {
                    HStack {
                        Label("\(wordCount) words", systemImage: "text.word.spacing")
                        Spacer()
                        Label(wrdEstimateString(for: wordCount, wpm: WPM), systemImage: "clock")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                    Button {
                        InteractionFeedback.impact(.medium)
                        showScreent = true
                    } label: {
                        Label("Practice This Script", systemImage: "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundStyle(.white)
                            .background(Color.pri)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.regularMaterial)
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showScreent) {
            Screen3Teleprompter(
                scriptItemID: scriptItemID,
                title: $title,
                script: $script,
                WPM: $WPM,
                isPresented: $showScreent
            )
        }
        #else
        .fullScreenCover(isPresented: $showScreent) {
            Screen3Teleprompter(
                scriptItemID: scriptItemID,
                title: $title,
                script: $script,
                WPM: $WPM,
                isPresented: $showScreent
            )
        }
        #endif
        #if os(macOS)
        .onChange(of: showScreent) { _, newValue in
            macSessionState.isSessionActive = newValue
        }
        #endif
        .onDisappear {
            typingResetTask?.cancel()
            #if os(macOS)
            macSessionState.isSessionActive = false
            #endif
        }
    }
}

#Preview {
    Screen22(
        scriptItemID: UUID(),
        title: .constant("untitled"),
        script: .constant("")
    )
}
