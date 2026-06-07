import Foundation
import UIKit

enum ScriptRenderService {
    nonisolated private static let fillerWords: Set<String> = [
        "um", "uh", "erm", "hmm"
    ]

    static func renderLines(text: String, fontSize: Double, width: CGFloat) -> [RenderedScriptLine] {
        let font = UIFont.systemFont(ofSize: fontSize)
        let rawLines = wrapLines(text, font: font, width: width)
        return rawLines.enumerated().map { index, line in
            RenderedScriptLine(
                index: index,
                displayText: line,
                normalizedTokens: normalizeTokens(line)
            )
        }
    }

    nonisolated static func normalizeTokens(_ text: String, droppingFillers: Bool = true) -> [String] {
        let lowered = text.lowercased()
        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                return Character(scalar)
            }
            return " "
        }
        let tokens = String(cleaned).split(whereSeparator: \.isWhitespace).map(String.init)
        guard droppingFillers else { return tokens }
        return tokens.filter { !fillerWords.contains($0) }
    }

    private static func wrapLines(_ text: String, font: UIFont, width: CGFloat) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var output: [String] = []
        var line = ""

        for word in words {
            let candidate = line.isEmpty ? word : "\(line) \(word)"
            let candidateWidth = (candidate as NSString).size(withAttributes: [.font: font]).width
            if candidateWidth <= width {
                line = candidate
            } else {
                if !line.isEmpty {
                    output.append(line)
                }
                line = word
            }
        }

        if !line.isEmpty {
            output.append(line)
        }
        return output
    }
}
