import SwiftUI

/// The app's palette, kept in one place rather than as color literals
/// scattered through the views.
///
/// These are chosen against the near-black space backdrop, which is why
/// the app is pinned to dark mode in `RickAndMortyApp`.
enum PortalTheme {
    /// Matches `AccentColor` in the asset catalog.
    static let portalGreen = Color(red: 0.486, green: 0.910, blue: 0.376)

    /// Dimmer green for card borders and hairlines.
    static let portalGlow = portalGreen.opacity(0.35)

    /// Translucent so the background image shows through the grid cards.
    static let cardFill = Color.black.opacity(0.45)

    static func color(for status: Character.Status) -> Color {
        switch status {
        case .alive: portalGreen
        case .dead: Color(red: 0.933, green: 0.290, blue: 0.290)
        case .unknown: .secondary
        }
    }
}

/// The space backdrop behind the search screen.
///
/// The artwork is a portrait phone wallpaper, so it's scaled with `.fill`
/// and clipped — in landscape or on an iPad the sides crop rather than
/// letterbox. The black base covers anything the image doesn't reach.
struct PortalBackground: View {
    var body: some View {
        Color.black
            .overlay {
                Image("PortalBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
