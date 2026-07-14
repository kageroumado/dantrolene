import SwiftUI

/// Dantrolene's design tokens — Adrafinil's system with the lilac identity. The visual language is
/// shared across kagerou apps: Liquid Glass surfaces, one accent doing the "active" talking (lilac
/// here, amber in Adrafinil), rounded hero type, and the same radius/spacing ladder.
enum Theme {
    // MARK: - Palette

    /// The lilac accent — "preventing lock". Backed by the AccentColor asset (light + dark variants).
    static let active = Color.accentColor
    /// Foreground for content sitting *on* the saturated lilac accent (e.g. a prominent button).
    /// The accent fill stays light in both light and dark mode, so this is a fixed dark indigo
    /// rather than `.primary` (which would flip to white in dark mode and fail contrast on lilac).
    static let onActive = Color(.sRGB, red: 0.07, green: 0.07, blue: 0.22, opacity: 1)
    /// Cool grey for the idle / locking-normally state.
    static let idle = Color.secondary
    /// Adrafinil's amber, used only where Dantrolene talks about Adrafinil (the promo surface).
    static let adrafinilAmber = Color.orange

    // MARK: - Geometry

    enum Radius {
        /// Outer cards / panels.
        static let card: CGFloat = 14
        /// Rows and grouped controls inside a card.
        static let inner: CGFloat = 10
        /// Small controls, chips, hover fills.
        static let control: CGFloat = 8
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }

    /// Fixed width of the menu-bar popover (matches Adrafinil; height always hugs content).
    static let popoverWidth: CGFloat = 320

    // MARK: - Shapes

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    }

    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    }
}

extension Font {
    /// Rounded title used for hero lines and page headers — friendlier than the default for a
    /// utility app.
    static let heroTitle = Font.system(.headline, design: .rounded).weight(.semibold)
    /// Rounded medium-weight body for emphasized names inside cards.
    static let cardTitle = Font.system(.body, design: .rounded).weight(.semibold)
}

// MARK: - Glass surfaces

extension View {
    /// Wraps the view in a Liquid Glass card with Dantrolene's standard radius. Pass `tint` to
    /// give the glass a cast (lilac for the active hero, amber for the Adrafinil promo).
    func glassCard(cornerRadius: CGFloat = Theme.Radius.card, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let glass: Glass = tint.map { .regular.tint($0) } ?? .regular
        return glassEffect(glass, in: shape)
    }
}
