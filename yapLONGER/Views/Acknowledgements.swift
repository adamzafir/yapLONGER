// layout inspired by growcalths acknowledgements page
import SwiftUI
import AVFoundation

struct Acknowledgements: View {
    @State private var audioPlayer: AVAudioPlayer?

    private func configureAudioSessionForPlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed:", error)
        }
    }

    private func playSound(named name: String, withExtension ext: String) {
        configureAudioSessionForPlayback()

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("Audio file not found: \(name).\(ext)")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Failed to init AVAudioPlayer:", error)
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    Section(header: Text("Packages & Frameworks")) {
                        ListItem(sfSymbol: "medal.star.fill", title: "Foundation Models", subtitle: "on-device models developed by Apple")
                        ListItem(sfSymbol: "sparkles", title: "Avyan Intelligence", subtitle: "Inspired by Avyan")
                            .contentShape(Rectangle())
                            .onTapGesture {
                                playSound(named: "cooked-dog-meme", withExtension: "mp3")
                            }
                    }
                }
            }
            .navigationTitle("Acknowledgements")
            .onAppear {
                configureAudioSessionForPlayback()
            }
        }
    }
}

#Preview {
    Acknowledgements()
}
