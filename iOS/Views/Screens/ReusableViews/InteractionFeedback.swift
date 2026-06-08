import SwiftUI

#if os(iOS)
import UIKit
#endif

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum InteractionFeedback {
    static func impact(_ style: FeedbackStyle = .light) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: style.uiStyle).impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    enum FeedbackStyle {
        case light
        case medium

        #if os(iOS)
        fileprivate var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light: return .light
            case .medium: return .medium
            }
        }
        #endif
    }
}
