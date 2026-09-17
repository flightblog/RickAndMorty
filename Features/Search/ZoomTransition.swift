import SwiftUI

/// Availability shims for the iOS 18 zoom navigation transition.
///
/// The app targets iOS 17, where `NavigationTransition` and
/// `matchedTransitionSource` don't exist. Wrapping them here keeps the
/// `if #available` checks out of the view bodies — the call sites read as
/// plain modifiers, and on iOS 17 they're no-ops that leave the standard
/// push animation in place.
extension View {
    /// Marks this view as the visual origin of a zoom transition.
    @ViewBuilder
    func zoomTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Opts a pushed destination into zooming from its matched source.
    @ViewBuilder
    func zoomNavigationTransition(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}

/// Availability shim for hiding the glass background iOS 26 draws behind a
/// toolbar item.
///
/// Same pattern as the zoom transition above. Earlier versions draw no such
/// background, so the fallback is a no-op. It's on `ToolbarContent` rather
/// than `View` because that's where SwiftUI defines it.
extension ToolbarContent {
    @ToolbarContentBuilder
    func hiddenToolbarItemBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
