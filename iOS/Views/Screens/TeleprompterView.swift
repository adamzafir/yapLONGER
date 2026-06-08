import SwiftUI

struct Screen3Teleprompter: View {
    var scriptItemID: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var title: String
    @Binding var script: String
    @Binding var WPM: Int
    @Binding var isPresented: Bool

    @AppStorage("fontSize") private var fontSize: Double = 28
    @StateObject private var session = PracticeSessionController()
    @State private var renderedLines: [RenderedScriptLine] = []
    @State private var reviewDraft = Review(cis: 0, wpm: 0)
    @State private var navigateToReview = false
    @State private var fontChoice: Settings.FontSizeChoice = .default
    @State private var customSize = 28.0
    @State private var showDiscardConfirmation = false
    @State private var finishTask: Task<Void, Never>?

    private var layoutWidth: CGFloat {
        horizontalSizeClass == .regular ? 620 : 340
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sessionStatus
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider()

                scriptReader

                Divider()

                practiceControls
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.regularMaterial)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(title.isEmpty ? "Practice" : title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToReview) {
                ReviewView(
                    review: $reviewDraft,
                    scriptItemID: scriptItemID,
                    showsSaveButton: true,
                    autoPersistOnAppear: true,
                    onDismiss: { isPresented = false }
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if session.isRecording {
                            showDiscardConfirmation = true
                        } else {
                            session.abandon()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close practice")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    fontMenu
                }
            }
            .alert("Practice Unavailable", isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(session.errorMessage ?? "")
            }
            .confirmationDialog(
                "Discard this practice?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Practice", role: .destructive) {
                    session.abandon()
                    dismiss()
                }
                Button("Keep Practicing", role: .cancel) {}
            } message: {
                Text("The current recording and unsaved feedback will be deleted.")
            }
            .onAppear {
                fontChoice = Settings.FontSizeChoice.fromStored(fontSize)
                customSize = fontSize
                recomputeLines()
            }
            .onChange(of: fontSize) { _, _ in recomputeLines() }
            .onChange(of: script) { _, _ in recomputeLines() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, session.isRecording {
                    finishPractice()
                }
            }
            .onChange(of: session.shouldFinishSession) { _, shouldFinish in
                if shouldFinish, session.isRecording {
                    finishPractice()
                }
            }
            .onDisappear {
                finishTask?.cancel()
                if !navigateToReview {
                    session.abandon()
                }
            }
        }
    }

    private var sessionStatus: some View {
        HStack(spacing: 12) {
            Label(session.formattedElapsedTime, systemImage: "timer")
                .monospacedDigit()

            Spacer()

            if session.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text(session.driftState == .drifting ? "Finding your place" : "Listening")
                }
                .foregroundStyle(session.driftState == .drifting ? .orange : .secondary)
            } else if session.isAnalyzing {
                Label("Analyzing", systemImage: "waveform.badge.magnifyingglass")
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(session.liveWordsPerMinute)")
                    .font(.headline)
                    .monospacedDigit()
                Text("WPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44)
        }
        .font(.subheadline.weight(.medium))
        .contentTransition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.isRecording)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.isAnalyzing)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(session.liveWordsPerMinute) words per minute")
    }

    private var scriptReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(renderedLines) { line in
                        Text(line.displayText)
                            .font(.system(size: fontSize, weight: line.index == session.activeLineIndex ? .semibold : .regular))
                            .foregroundStyle(lineColor(for: line.index))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if line.index == session.activeLineIndex {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.pri.opacity(0.12))
                                }
                            }
                            .id(line.index)
                            .accessibilityLabel(
                                line.index == session.activeLineIndex
                                    ? "Current line, \(line.displayText)"
                                    : line.displayText
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 24)
            }
            .onChange(of: session.activeLineIndex) { _, newIndex in
                if reduceMotion {
                    proxy.scrollTo(newIndex, anchor: .center)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private var practiceControls: some View {
        VStack(spacing: 10) {
            Button {
                if session.isRecording {
                    InteractionFeedback.impact(.medium)
                    finishPractice()
                } else {
                    InteractionFeedback.impact(.medium)
                    Task {
                        await session.start()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if session.isAnalyzing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: session.isRecording ? "stop.fill" : "mic.fill")
                    }
                    Text(
                        session.isAnalyzing
                            ? "Analyzing delivery..."
                            : (session.isRecording ? "Finish practice" : "Start practice")
                    )
                    .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(.white)
                .background(session.isRecording ? Color.red : Color.pri)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(session.isAnalyzing || renderedLines.isEmpty)

            Text(
                session.isRecording
                    ? "\(session.recognizedWordCount) words recognized"
                    : "Speak naturally. The script follows your voice."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var fontMenu: some View {
        Menu {
            Picker("Font Size", selection: $fontChoice) {
                ForEach(Settings.FontSizeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .onChange(of: fontChoice) { _, choice in
                if let preset = choice.presetValue {
                    fontSize = preset
                    customSize = preset
                }
            }

            if fontChoice == .custom {
                Slider(value: $customSize, in: 14...60, step: 1)
                    .onChange(of: customSize) { _, value in
                        fontSize = value
                    }
            }
        } label: {
            Image(systemName: "textformat.size")
        }
        .disabled(session.isRecording || session.isAnalyzing)
        .accessibilityLabel("Teleprompter font size")
    }

    private func recomputeLines() {
        #if os(iOS)
        renderedLines = ScriptRenderService.renderLines(
            text: script,
            fontSize: fontSize,
            width: layoutWidth
        )
        #else
        let words = script.split(whereSeparator: \.isWhitespace).map(String.init)
        renderedLines = words.enumerated().map { index, word in
            RenderedScriptLine(
                index: index,
                displayText: word,
                normalizedTokens: ScriptRenderService.normalizeTokens(word)
            )
        }
        #endif
        session.configure(lines: renderedLines)
    }

    private func lineColor(for index: Int) -> Color {
        if index < session.activeLineIndex {
            return .secondary
        }
        return .primary
    }

    private func finishPractice() {
        guard finishTask == nil else { return }
        finishTask = Task {
            defer { finishTask = nil }
            guard let review = await session.stopAndAnalyze(), !Task.isCancelled else {
                return
            }
            reviewDraft = review
            WPM = review.wpm
            InteractionFeedback.success()
            navigateToReview = true
        }
    }
}
