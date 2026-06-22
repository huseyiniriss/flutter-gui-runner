import SwiftUI

// MARK: - Design tokens
// Single source of truth for spacing, radii, sizing, and motion.
// No view should hardcode these values inline.

enum Theme {
    // Spacing scale
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24

    // Corner radii
    static let radius: CGFloat = 8
    static let radiusLg: CGFloat = 12

    // Window / panel sizing
    static let windowMinW: CGFloat = 620
    static let windowMinH: CGFloat = 720
    static let menuWidth: CGFloat = 460
    static let logHeight: CGFloat = 200

    // Motion — every interactive element shares one curve/duration.
    static let press: Animation = .spring(response: 0.25, dampingFraction: 0.7)
    static let appear: Animation = .easeOut(duration: 0.2)
}

// MARK: - Buttons (consistent, with press feedback)

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Rendered(c: configuration) }
    private struct Rendered: View {
        let c: Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            c.label
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, Theme.s2)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Theme.radius))
                .foregroundStyle(.white)
                .opacity(enabled ? (c.isPressed ? 0.85 : 1) : 0.4)
                .scaleEffect(c.isPressed ? 0.97 : 1)
                .animation(Theme.press, value: c.isPressed)
        }
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Rendered(c: configuration) }
    private struct Rendered: View {
        let c: Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            c.label
                .font(.body)
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, Theme.s2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.radius))
                .foregroundStyle(.primary)
                .opacity(enabled ? (c.isPressed ? 0.7 : 1) : 0.4)
                .scaleEffect(c.isPressed ? 0.97 : 1)
                .animation(Theme.press, value: c.isPressed)
        }
    }
}

/// Small icon-only button (refresh, trash, add) with consistent hit area.
struct IconButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Rendered(c: configuration) }
    private struct Rendered: View {
        let c: Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            c.label
                .frame(width: 26, height: 26)
                .background(.quaternary.opacity(c.isPressed ? 0.8 : 0.5),
                            in: RoundedRectangle(cornerRadius: Theme.radius - 2))
                .foregroundStyle(.secondary)
                .opacity(enabled ? 1 : 0.4)
                .scaleEffect(c.isPressed ? 0.92 : 1)
                .animation(Theme.press, value: c.isPressed)
        }
    }
}

extension ButtonStyle where Self == PrimaryButton {
    static var primary: PrimaryButton { .init() }
}
extension ButtonStyle where Self == SecondaryButton {
    static var secondary: SecondaryButton { .init() }
}
extension ButtonStyle where Self == IconButton {
    static var icon: IconButton { .init() }
}

// MARK: - Building blocks

/// The consistent shell every tab uses: padded title row + content (+ log).
struct TabScaffold<Actions: View, Content: View>: View {
    let title: String
    var icon: String? = nil
    var showsLog: Bool = true
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: Theme.s3) {
                HStack(spacing: Theme.s2) {
                    if let icon { Image(systemName: icon).foregroundStyle(.tint) }
                    Text(title).font(.title3.weight(.semibold))
                    Spacer()
                    actions()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.s3) {
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Theme.s1)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(minHeight: 120)            // always keep the content visible
                if showsLog {
                    // Cap the terminal so it can't swallow the content above.
                    ResizableLogPane(maxHeight: max(140, geo.size.height - 300))
                }
            }
            .padding(Theme.s4)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

extension TabScaffold where Actions == EmptyView {
    init(title: String, icon: String? = nil, showsLog: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, icon: icon, showsLog: showsLog,
                  actions: { EmptyView() }, content: content)
    }
}

/// A titled card used to group options/fields consistently.
struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLg).stroke(.quaternary))
    }
}

/// Consistent empty/placeholder state.
struct EmptyState: View {
    let title: String, symbol: String, hint: String
    var body: some View {
        VStack(spacing: Theme.s2) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(hint).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.s4)
    }
}
