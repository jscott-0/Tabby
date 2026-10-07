import SwiftUI

// Liquid Glass on iOS 26, with the closest iOS 18 look as the fallback. Views use these instead of
// picking button styles and backgrounds themselves, so the app reads as one design on either OS.

extension View {
    /// The main action on a screen: Save, Continue, Buy.
    @ViewBuilder func primaryActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Supporting actions next to content: Open in app, Paste a link.
    @ViewBuilder func secondaryActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// A glass surface behind floating content (banners, chips, cards that sit over a scroll view).
    /// `tint` colors the glass; `interactive` makes it respond to touch like a control.
    @ViewBuilder func glassSurface<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if let tint { shape.fill(tint.opacity(0.85)) }
                }
            }
        }
    }

    /// A bar of buttons pinned to the bottom. On iOS 26 it floats over the content with a soft scroll
    /// edge instead of an opaque background.
    func floatingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(FloatingBar(edge: .bottom, bar: bar()))
    }

    /// Same as `floatingBottomBar`, for filter rows under the navigation bar.
    func floatingTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(FloatingBar(edge: .top, bar: bar()))
    }
}

private struct FloatingBar<Bar: View>: ViewModifier {
    let edge: VerticalEdge
    let bar: Bar

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: edge, spacing: 0) { bar }
        } else {
            content.safeAreaInset(edge: edge, spacing: 0) { bar.background(.bar) }
        }
    }
}

/// Groups nearby glass shapes so they blend and morph together on iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Toolbar buttons that become iOS 26's icon-only glass circles (xmark, checkmark) and stay text
/// buttons before that. The text stays as the accessibility label either way.
struct SheetCloseButton: View {
    var title = "Cancel"
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(title, systemImage: "xmark", action: action)
                .labelStyle(.iconOnly)
        } else {
            Button(title, action: action)
        }
    }
}

struct SheetConfirmButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(title, systemImage: "checkmark", action: action)
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
        } else {
            Button(title, action: action)
        }
    }
}

enum Symbols {
    /// iOS 26 draws the circle as glass, so the symbol drops its own.
    static var more: String {
        if #available(iOS 26.0, *) { "ellipsis" } else { "ellipsis.circle" }
    }
}
