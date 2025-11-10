import SwiftUI

struct Screen4: View {
    @State private var WPM = 120
    @State private var LGBW = 7
    @State private var CIS = 20
    @State private var score: Int = 2
    @State private var scoreTwo: Double = 67
    var body: some View {
        NavigationStack {
            VStack {
                Form{
                    Section("Result"){
                        LabeledContent {
                            Text(String(WPM))
                        } label: {
                            Text("Words per minute")
                        }
                        LabeledContent {
                            Text(String(LGBW))
                        } label: {
                            Text("Longest gap between words (seconds)")
                        }
                        LabeledContent {
                            Text(String(CIS))
                        } label: {
                            Text("Consistency in speech (%)")
                        }
                    }
                    Section("Score"){
                        VStack {
                            TabView {
                                    SemiCircleGauge(progress: Double(score) / 3.0, label: "\(score)/3")
                                        .frame(height: 160)
                                        .padding(.horizontal)
                                        .padding(.top, 8)
                                    SemiCircleGauge(progress: max(0.0, min(1.0, scoreTwo / 100.0)), label: "\(Int(scoreTwo))%")
                                        .frame(height: 160)
                                        .padding(.horizontal)
                                        .padding(.top, 8)
                            }
                            .tabViewStyle(.page)
                            .indexViewStyle(.page(backgroundDisplayMode: .always))
                            
                        }
                        .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16))
                        
                    }
                    NavigationLink {
                        Screen5()
                    } label: {
                        Text("Playback")
                            .bold()
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
            .navigationTitle("Review")
        }
    }
    
    
    struct SemiCircleGauge: View {
        // progress expected 0.0 ... 1.0
        var progress: Double
        var lineWidth: CGFloat = 16
        var label: String? = nil
        
        var body: some View {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let radius = size / 2
                ZStack {
                    // Background arc (gray)
                    Arc(startAngle: .degrees(180), endAngle: .degrees(360))
                        .stroke(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    // Progress arc (blue)
                    Arc(startAngle: .degrees(180), endAngle: .degrees(180 + 180 * progress))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .animation(.easeInOut(duration: 0.4), value: progress)
                    // Optional percentage label
                    if let label {
                        Text(label)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.primary)
                            .offset(y: size * 0.15)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
    
    // A simple arc shape that draws from startAngle to endAngle with center at bottom of the view to make a semicircle
    struct Arc: Shape {
        var startAngle: Angle
        var endAngle: Angle
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let width = rect.width
            let height = rect.height
            let center = CGPoint(x: rect.midX, y: rect.maxY)
            let radius = min(width, height)
            path.addArc(center: center,
                        radius: radius,
                        startAngle: startAngle,
                        endAngle: endAngle,
                        clockwise: false)
            
            return path
        }
    }
}

#Preview {
    Screen4()
}
