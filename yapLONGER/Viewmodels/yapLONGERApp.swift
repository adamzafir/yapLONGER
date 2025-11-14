import SwiftUI

@main
struct yapLONGERApp: App {
    @StateObject private var recordingStore = RecordingStore()
    
    var body: some Scene {
        WindowGroup {
            TabHolder()
                .environmentObject(recordingStore)
        }
    }
}
