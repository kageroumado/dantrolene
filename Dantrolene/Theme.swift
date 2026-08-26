import Propofol
import SwiftUI

/// Dantrolene's palette on top of Propofol's shared tokens — the lilac identity: one accent doing
/// the "active" talking, cool grey for locking normally.
extension Theme {
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
}

extension Font {
    /// Rounded medium-weight body for emphasized names inside cards.
    static let cardTitle = Font.system(.body, design: .rounded).weight(.semibold)
}
