import SwiftUI
import Foundation

struct startGame: View {
    
@State private var currentDate = Date.now
    @State private var elapsedTime: Int = 0
    @State private var timer: Timer? = nil

    
    @State private var showingAlert = false
    var formattedTime: String {
        let minutes = elapsedTime / 60
        let seconds = elapsedTime % 60
        return String(format: "%02d:%02d", minutes, seconds)
        
    }
    
    var body: some View {
        
            
            VStack {
                

                VStack{
                    Spacer()
                    Text("Time: \(formattedTime)")
                        .bold()
                        .monospaced()
                        .font(.largeTitle)
                        .padding(7)
                        .background(Color(red:12 , green:12 , blue: 12))
                        .clipShape(RoundedRectangle (cornerRadius: 10))
                        .padding()
                        .onAppear {
                            elapsedTime = 0
                            timer?.invalidate()
                            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                                elapsedTime += 1
                            }
                        }
                }
            }
        }
    }




#Preview {
    startGame()
}
