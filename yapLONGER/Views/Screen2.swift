import SwiftUI
import FoundationModels

struct Screen2: View {
    @Binding var title: String
    @Binding var script: String
    
    @State private var showScreen = false
    @State private var showScreent = false
    @FocusState private var isEditingScript: Bool
    
    @State private var rewriting = false
    @State private var rewritePrompt = """
    Rewrite this script. Reply with ONLY the rewritten version of this script...
    """
    
    @State private var showPromptDialog = false
    @State private var rewriteError: String? = nil
    
    var body: some View {
        NavigationStack {
        TabView {
                VStack {
                    TextField("Untitled Script", text: $title)
                        .font(.title)
                        .fontWeight(.bold)
                        .padding()
                    
                    TextEditor(text: $script)
                        .focused($isEditingScript)
                        .padding(.horizontal)
                        .frame(maxHeight: .infinity)
                    
                    Spacer()
                }
                .navigationTitle(title.isEmpty ? "Untitled Script" : title)
                .lineLimit(3)
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
                        }
                    }.disabled(rewriting)
                    
                    Button("Cancel", role: .cancel) {}
                }
                .overlay {
                    if rewriting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                    }
                }
            }
        .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showScreen = true
                    } label: {
                        Image(systemName: "music.microphone")
                    } //change the sf symbols later
                    Button {
                        showScreent = true
                    } label: {
                        Image(systemName: "music.microphone")
                    }
                }
            
            
            ToolbarItemGroup(placement: .keyboard) {
                Button {
                    showPromptDialog = true
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                
                Spacer()
                
                Button {
                    isEditingScript = false
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }

        }
        .tabViewBottomAccessory {
            Text("Word Count: \(script.split { $0.isWhitespace }.count)")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $showScreent) {
            Screen3Teleprompter(title: $title, script: $script)
        }
        .fullScreenCover(isPresented: $showScreen) {
            Screen3Keywords(title: $title, script: $script)
        }
    }
}


#Preview {
    Screen2(
        title: .constant("untitled"),
        script: .constant("This is a test script.")
    )
}
