import SwiftUI
import TabbyKit

@main
struct TabbyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Phase 0 placeholder: paste a profile link to see the tier-1 parse. Replaced by Spaces in Phase 1.
struct ContentView: View {
    @State private var text = ""

    private var parsed: ParsedProfileURL? {
        ProfileURLParser.firstURL(in: text).map(ProfileURLParser.parse)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Paste a profile link") {
                    TextField("https://www.instagram.com/…", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let parsed {
                    Section("Parsed") {
                        LabeledContent("Platform", value: parsed.platform.rawValue)
                        LabeledContent("Handle", value: parsed.handle ?? "—")
                        LabeledContent("Kind", value: String(describing: parsed.kind))
                    }
                }
            }
            .navigationTitle("Tabby")
        }
    }
}

#Preview {
    ContentView()
}
