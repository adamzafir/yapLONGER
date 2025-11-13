import SwiftUI

struct ListItem: View {
    var sfSymbol: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            
            VStack {
                Spacer(minLength: 0)
                if title != "Avyan Intelligence" {
                    Image(systemName: sfSymbol)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: sfSymbol)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.secondary)
                        .appleIntelligenceGradient(start: .top)
                }
                    
                Spacer(minLength: 0)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                if title != "Avyan Intelligence" {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)
                } else {
                    Text(title)
                        .fontWeight(.semibold)
                        .appleIntelligenceGradient()
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
