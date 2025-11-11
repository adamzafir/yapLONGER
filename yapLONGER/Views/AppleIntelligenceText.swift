import SwiftUI

struct AppleIntelligenceGradient: ViewModifier {
    var start: UnitPoint = .leading
    var end: UnitPoint = .trailing
    
    private var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.19, green: 0.54, blue: 1.00), location: 0.00),
                .init(color: Color(red: 0.45, green: 0.38, blue: 1.00), location: 0.18),
                .init(color: Color(red: 0.74, green: 0.37, blue: 1.00), location: 0.40),
                .init(color: Color(red: 1.00, green: 0.33, blue: 0.55), location: 0.67), 
                .init(color: Color(red: 1.00, green: 0.63, blue: 0.23), location: 1.00)
            ],
            startPoint: start,
            endPoint: end
        )
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(gradient)
            .mask(content)
    }
}

extension View {
    func appleIntelligenceGradient(start: UnitPoint = .leading,
                                   end: UnitPoint = .trailing) -> some View {
        modifier(AppleIntelligenceGradient(start: start, end: end))
    }
}
