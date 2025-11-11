import SwiftUI

enum Tabs {
    case scripts
    case settings
    case add
}

struct TabHolder: View {
    @State private var selectedTab: Tabs = .scripts
    @State var showScreen: Bool = false
    @StateObject private var viewModel = Screen2ViewModel()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Scripts", systemImage: "swirl.circle.righthalf.filled", value: Tabs.scripts) {
                Screen1(viewModel: viewModel)
            }
            
            Tab("Settings", systemImage: "gear", value: Tabs.settings) {
                Settings()
            }
            
            Tab("Add", systemImage: "plus", value: Tabs.add, role: .search) {
                Color.clear
                    .onAppear {
                        var newItem = ScriptItem(
                            id: UUID(),
                            title: "Untitled Script",
                            scriptText: "Type something..."
                        )
                        viewModel.scriptItems.append(newItem)
                        selectedTab = .scripts
                    }
            }
        }
    }
}


#Preview {
    TabHolder()
}
