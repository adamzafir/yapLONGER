import SwiftUI

struct RecordButtonView: View {
    @Binding var isRecording: Bool
    @State private var buttonCircle: CGFloat = 60
    @State private var buttonSquare: CGFloat = 30
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray, lineWidth: 5)
                    .frame(width: 75, height: 75)
                
                RoundedRectangle(cornerRadius: isRecording ? 5 : 50)
                    .foregroundStyle(.red)
                    .frame(
                        maxWidth: isRecording ? buttonSquare : buttonCircle,
                        maxHeight: isRecording ? buttonSquare : buttonCircle)
            }
        }
        .padding(.vertical, 20)
        .animation(.snappy, value: isRecording)
    }
}
