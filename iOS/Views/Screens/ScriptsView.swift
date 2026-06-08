import SwiftUI

private enum ScriptRoute: Hashable {
    case editor(UUID)
    case reviews(UUID)
}

struct Screen1: View {
    @ObservedObject var viewModel: Screen2ViewModel
    @State private var path: [ScriptRoute] = []
    @State private var pendingDeletion: UUID?
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Group {
                    if viewModel.scriptItems.isEmpty {
                        ContentUnavailableView {
                            Label("No Scripts", systemImage: "list.bullet")
                        } description: {
                            Text("Create a script, then practice it with live voice tracking.")
                        }
                       
                    } else {
                        List {
                            ForEach($viewModel.scriptItems) { $item in
                                NavigationLink(value: ScriptRoute.editor(item.id)) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title.isEmpty ? "Untitled Script" : item.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        HStack(spacing: 6) {
                                            Text("\(item.scriptText.split(whereSeparator: \.isWhitespace).count) words")
                                            Text("·")
                                            Text("\(item.pastReviews.reviewsItems.count) reviews")
                                            if item.lastAccessed != .distantPast {
                                                Text("·")
                                                Text(item.lastAccessed, style: .relative)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        path.append(.reviews(item.id))
                                    } label: {
                                        Label("Past Reviews", systemImage: "clock.arrow.circlepath")
                                    }
                                .tint(.pri)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeletion = item.id
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                
                VStack {
                    Spacer()
                    Button {
                        InteractionFeedback.impact()
                        viewModel.addNewScriptAtFront()
                        if let id = viewModel.scriptItems.first?.id {
                            path.append(.editor(id))
                        }
                    } label: {
                        Label("New Script", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.vertical, 15)
                            .background(Color.pri)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("Scripts")
            .confirmationDialog("Delete this script?", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Script", role: .destructive) {
                    guard let id = pendingDeletion,
                          let index = viewModel.scriptItems.firstIndex(where: { $0.id == id }) else {
                        return
                    }
                    deleteItems(at: IndexSet(integer: index))
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Its practice history will also be removed.")
            }
            .navigationDestination(for: ScriptRoute.self) { route in
                switch route {
                case .editor(let id):
                    if let item = binding(for: id) {
                        Screen22(
                            scriptItemID: id,
                            title: item.title,
                            script: item.scriptText
                        )
                        .onAppear { viewModel.markAccessed(id: id) }
                    } else {
                        ContentUnavailableView("Script not found", systemImage: "exclamationmark.triangle")
                    }
                case .reviews(let id):
                    PastReviewsView(scriptID: id)
                        .environmentObject(viewModel)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        Settings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        viewModel.scriptItems.remove(atOffsets: offsets)
    }

    private func deleteItems(at index: Int) {
        guard index < viewModel.scriptItems.count else { return }
        viewModel.scriptItems.remove(at: index)
    }

    private func binding(for id: ScriptItem.ID) -> Binding<ScriptItem>? {
        guard let initialValue = viewModel.scriptItems.first(where: { $0.id == id }) else {
            return nil
        }
        return Binding(
            get: {
                viewModel.scriptItems.first(where: { $0.id == id }) ?? initialValue
            },
            set: { updatedValue in
                guard let index = viewModel.scriptItems.firstIndex(where: { $0.id == id }) else {
                    return
                }
                viewModel.scriptItems[index] = updatedValue
            }
        )
    }
}
