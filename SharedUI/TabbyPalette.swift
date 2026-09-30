import SwiftUI
import TabbyKit

/// Tag and Space colors, indexed by `colorIndex`. Keep `colors.count == TagPalette.count`.
enum TabbyPalette {
    static let colors: [Color] = [.blue, .purple, .pink, .red, .orange, .yellow, .green, .mint, .teal, .indigo]
    static let names = ["Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Mint", "Teal", "Indigo"]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    /// A stable color for a name, for avatars without a photo.
    static func color(for name: String) -> Color {
        color(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF })
    }
}

extension Platform {
    /// SF Symbol shown in badges (no brand logos).
    var symbol: String {
        switch self {
        case .linkedin: "briefcase.fill"
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        case .other: "globe"
        }
    }

    var tint: Color {
        switch self {
        case .linkedin: Color(red: 0.04, green: 0.40, blue: 0.76)
        case .instagram: Color(red: 0.84, green: 0.16, blue: 0.46)
        case .tiktok: Color(red: 0.0, green: 0.52, blue: 0.58)
        case .other: .gray
        }
    }
}

extension Binding where Value == Bool {
    /// True while `source` holds a value; setting false clears it. For alerts and dialogs driven by an optional.
    init<Wrapped>(isPresent source: Binding<Wrapped?>) {
        self.init(get: { source.wrappedValue != nil }, set: { if !$0 { source.wrappedValue = nil } })
    }
}
