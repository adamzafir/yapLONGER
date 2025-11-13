import SwiftUI

struct Settings: View {
    enum ColourScheme: String, CaseIterable, Identifiable {
        case light
        case dark
        case system
        
        var id: String { rawValue }
        var title: String {
            switch self {
            case .light: return "Light"
            case .dark: return "Dark"
            case .system: return "Default"
            }
        }
    }
    
    @AppStorage("appColorScheme") private var storedFlavorRawValue: String = ColourScheme.system.rawValue
    
    private var storedColourScheme: ColourScheme {
        get { ColourScheme(rawValue: storedFlavorRawValue) ?? .system }
        set { storedFlavorRawValue = newValue.rawValue }
    }
    
    private var colourSchemeBinding: Binding<ColourScheme> {
        Binding(
            get: { ColourScheme(rawValue: storedFlavorRawValue) ?? .system },
            set: { storedFlavorRawValue = $0.rawValue }
        )
    }
    
    @AppStorage("fontSize") private var fontSize: Double = 28
    
    
    private enum FontSizeChoice: Hashable, CaseIterable, Identifiable {
        case extraSmall
        case small
        case `default`
        case large
        case massive
        case custom
        
        var id: Self { self }
        
        var title: String {
            switch self {
            case .extraSmall: return "XS"
            case .small: return "S"
            case .default: return "Default"
            case .large: return "L"
            case .massive: return "XL"
            case .custom: return "Custom"
            }
        }
        
        var presetValue: Double? {
            switch self {
            case .extraSmall: return 10
            case .small: return 20
            case .default: return 28
            case .large: return 40
            case .massive: return 50
            case .custom: return nil
            }
        }
        
        static func fromStored(_ value: Double) -> FontSizeChoice {
            switch value {
            case 10: return .extraSmall
            case 20: return .small
            case 28: return .default
            case 40: return .large
            case 50: return .massive
            default: return .custom
            }
        }
    }
    
    @State private var fontChoice: FontSizeChoice = .default
    @State private var customSize: Double = 28
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: colourSchemeBinding) {
                        ForEach(ColourScheme.allCases) { scheme in
                            Text(scheme.title).tag(scheme)
                        }
                    }
                }
                
                Section(header: Text("Teleprompter Font size")) {
                    Picker("Font size", selection: Binding(
                        get: { fontChoice },
                        set: { newChoice in
                            fontChoice = newChoice
                            if let preset = newChoice.presetValue {
                                
                                fontSize = preset
                                customSize = preset
                            } else {
                                
                                customSize = min(max(fontSize, 10), 60)
                            }
                        }
                    )) {
                        ForEach(FontSizeChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if fontChoice == .custom {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Custom size")
                                Spacer()
                                Text("\(Int(customSize)) pt")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { customSize },
                                set: { newValue in
                                    customSize = newValue
                                    fontSize = newValue
                                }
                            ), in: 10...60, step: 1)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                NavigationLink {
                    Acknowledgements()
                } label: {
                    Text("Acknowledgements")
                }
            }
            .onAppear {
                
                let initialChoice = FontSizeChoice.fromStored(fontSize)
                fontChoice = initialChoice
                customSize = initialChoice.presetValue ?? min(max(fontSize, 10), 60)
            }
            .preferredColorScheme(storedColourScheme.colorScheme)
            .navigationTitle("Settings")
        }
    }
}

extension Settings.ColourScheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

#Preview {
    Settings()
}
