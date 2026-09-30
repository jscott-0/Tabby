import SwiftData
import SwiftUI
import TabbyKit
import UIKit

/// Stored avatar, else the profile's avatar URL, else initials on a stable color.
struct AvatarView: View {
    let name: String
    let imageData: Data?
    let imageURL: URL?
    var size: CGFloat = 40

    init(name: String, imageData: Data?, imageURL: URL?, size: CGFloat = 40) {
        self.name = name
        self.imageData = imageData
        self.imageURL = imageURL
        self.size = size
    }

    init(person: Person, size: CGFloat = 40) {
        self.init(name: person.title, imageData: person.avatarData, imageURL: person.avatarURL, size: size)
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let imageURL {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    initials
                }
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            Circle().fill(TabbyPalette.color(for: name).gradient)
            Text(Self.initials(name))
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    static func initials(_ name: String) -> String {
        let words = name.split { $0 == " " || $0 == "@" || $0 == "_" || $0 == "-" || $0 == "." }
        let letters = words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }
}

struct PlatformBadge: View {
    let platform: Platform
    var showsName = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: platform.symbol)
            if showsName { Text(platform.displayName) }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(platform.tint))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(platform.displayName)
    }
}
