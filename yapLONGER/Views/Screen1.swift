import SwiftUI

struct Screen1: View {
    @ObservedObject var viewModel: Screen2ViewModel

    var body: some View {
        NavigationStack {
            Form {
                ForEach($viewModel.scriptItems) { $item in
                    NavigationLink {
                        Screen2(title: $item.title, script: $item.scriptText)
                    } label: {
                        Text(item.title)
                    }
                }
                .onDelete(perform: deleteItems) 
            }
            .navigationTitle("Scripts")
           
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        viewModel.scriptItems.remove(atOffsets: offsets)
    }
}



#Preview {
    Screen1(viewModel: Screen2ViewModel())
}
