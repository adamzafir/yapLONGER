import SwiftUI

enum Tabs: Hashable {
    case scripts
    case settings
    case add
}

struct TabHolder: View {
    @State private var selectedTab: Tabs = .scripts
    @StateObject private var viewModel = Screen2ViewModel()
    var body: some View {
        TabView(selection: $selectedTab) {

            Tab("Scripts", systemImage: "text.document", value: Tabs.scripts) {
                NavigationStack {
                    Screen1(viewModel: viewModel)
                        .navigationTitle("Scripts")
                }
            }

            Tab("Settings", systemImage: "gear", value: Tabs.settings) {
                NavigationStack {
                    Settings()
                        .navigationTitle("Settings")
                }
            }

            Tab("Add", systemImage: "plus", value: Tabs.add, role: .search) {
                Color.clear
                    .onAppear {
                        let newItem = ScriptItem(
                            id: UUID(),
                            title: "Untitled Script",
                            scriptText: "Type something..."
                        )
                        viewModel.scriptItems.append(newItem)
                        selectedTab = .scripts
                    }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    TabHolder()
}
