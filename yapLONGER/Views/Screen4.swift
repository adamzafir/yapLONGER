import SwiftUI

struct Screen4: View {
    @State private var WPM = 120
    @Binding var LGBW: Int
    @State private var CIS = 70
    @State private var score: Int = 2
    @State private var scoreTwo: Double = 67
    @Binding var elapsedTime: Int
    @Binding var wordCount: Int
    private func wpmPercentage(_ wpm: Int) -> Double {
        if wpm <= 120 {
            
            let pct = 100 + (wpm - 120)
            return Double(max(0, min(100, pct)))
        } else {
            
            let pct = 100 + (wpm - 120)
            return Double(max(0, min(200, pct)))
        }
    }
    
    private func lgbwPercentage(_ lgbw: Int) -> Double {
        if lgbw <= 5 { return 100 }
        
        let over = min(10, max(6, lgbw))
        let stepsAbove5 = over - 5
        let pct = 100 - stepsAbove5 * 20
        return Double(max(0, pct))
    }
    
    private func cisPercentage(_ cis: Int) -> Double {
        if cis >= 80 && cis <= 85 { return 100 }
        if cis > 85 {
            let over = cis - 85
            let pct = 100 - over * 6
            return Double(max(0, min(100, pct)))
        }
        return Double(max(0, min(100, cis)))
    }
    
    private func computeScoreThreePoint(wpmPct: Double, lgbwPct: Double, cisPct: Double) -> Int {
        
        let wpmIsIdeal = Int(round(wpmPct)) == 100
        let lgbwIsIdeal = Int(round(lgbwPct)) == 100
        let cisIsIdeal = CIS >= 80 && CIS <= 85
        return (wpmIsIdeal && lgbwIsIdeal && cisIsIdeal) ? 3 : 2
    }
    
    private func updateScores() {
        let wpmPct = wpmPercentage(WPM)
        let lgbwPct = lgbwPercentage(LGBW)
        let cisPct = cisPercentage(CIS)
        
        let overall = (wpmPct + lgbwPct + cisPct) / 3.0
        scoreTwo = max(0, min(100, overall))
        score = computeScoreThreePoint(wpmPct: wpmPct, lgbwPct: lgbwPct, cisPct: cisPct)
    }
    
    private func updateWPMFromBindings() {
        // Compute words per minute safely from wordCount and elapsedTime (seconds)
        guard elapsedTime > 0 else {
            WPM = 0
            return
        }
        let minutes = Double(elapsedTime) / 60.0
        let computed = Int(round(Double(wordCount) / minutes))
        WPM = max(0, computed)
    }
    
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
                    .onChange(of: WPM) { _, _ in updateScores() }
                    .onChange(of: LGBW) { _, _ in updateScores() }
                    .onChange(of: CIS) { _, _ in updateScores() }
                    .onChange(of: elapsedTime) { _, _ in
                        updateWPMFromBindings()
                        updateScores()
                    }
                    .onChange(of: wordCount) { _, _ in
                        updateWPMFromBindings()
                        updateScores()
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
                        Screen5(scoreTwo: $scoreTwo)
                    } label: {
                        Text("Playback")
                            .bold()
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
            .onAppear {
                updateWPMFromBindings()
                updateScores()
            }
            .navigationTitle("Review")
        }
    }
    
    
    struct SemiCircleGauge: View {
       
        var progress: Double
        var lineWidth: CGFloat = 16
        var label: String? = nil
        
        var body: some View {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let radius = size / 2
                ZStack {
                    
                    Arc(startAngle: .degrees(180), endAngle: .degrees(360))
                        .stroke(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    
                    Arc(startAngle: .degrees(180), endAngle: .degrees(180 + 180 * progress))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .animation(.easeInOut(duration: 0.4), value: progress)
                    
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
    
   
    struct Arc: Shape {
        var startAngle: Angle
        var endAngle: Angle
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let width = rect.width
            let height = rect.height
            let center = CGPoint(x: rect.midX, y: rect.maxY)
            let radius = min(width, height) / 2
            path.addArc(center: center,
                        radius: radius,
                        startAngle: startAngle,
                        endAngle: endAngle,
                        clockwise: false,
                        transform: .identity)
            
            return path
        }
    }
}

#Preview {
    Screen4(LGBW: .constant(0), elapsedTime: .constant(0), wordCount: .constant(0))
}
