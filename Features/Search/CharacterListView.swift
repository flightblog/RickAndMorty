import SwiftUI

struct CharacterListView: View {
    @State private var viewModel = CharacterListViewModel()

    /// Ties each grid cell to the detail view's hero image so the
    /// picture zooms from one to the other instead of the whole screen
    /// sliding. iOS 18+; on iOS 17 the standard push is used.
    @Namespace private var zoomNamespace

    /// Adaptive rather than a fixed count: two columns on a phone in
    /// portrait, more in landscape or on a larger device, and it collapses
    /// to one when a large Dynamic Type size makes the cells wider. The
    /// minimum is sized so a name like "Rick Sanchez" doesn't truncate.
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            // The banner is part of the scroll content's container, so it
            // sits *below* the navigation bar. Putting it in a
            // `.safeAreaInset(edge: .top)` on this content instead would
            // inset above the bar and hide the title.
            VStack(spacing: 0) {
                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage) {
                        Task { await viewModel.retry() }
                    }
                }
                results
            }
            .background {
                PortalBackground()
            }
            // Hiding the bar's material lets the artwork run under it.
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("Rick and Morty")
            .navigationDestination(for: Character.self) { character in
                CharacterDetailView(character: character)
                    .zoomNavigationTransition(
                        sourceID: character.id,
                        in: zoomNamespace
                    )
            }
            .searchable(text: $viewModel.searchText, prompt: "Search by name")
            .task(id: viewModel.searchText) {
                await viewModel.search(for: viewModel.searchText)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Always in the hierarchy, toggled by opacity: a
                    // `ToolbarItem` that appears and disappears behind an
                    // `if` animates unreliably and can fail to show at all.
                    ProgressView()
                        .opacity(viewModel.isLoading ? 1 : 0)
                        .accessibilityHidden(!viewModel.isLoading)
                        .accessibilityLabel("Searching")
                }
                // `.opacity` fades the spinner but not the glass capsule
                // iOS 26 draws behind a toolbar item, which reads as a
                // stray dark circle now the bar is transparent.
                .hiddenToolbarItemBackground()
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if !viewModel.characters.isEmpty {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.characters) { character in
                        NavigationLink(value: character) {
                            CharacterCell(character: character)
                        }
                        // Without this the whole cell renders in the
                        // accent color, since `NavigationLink` styles its
                        // label as a button.
                        .buttonStyle(.plain)
                        .zoomTransitionSource(
                            id: character.id,
                            in: zoomNamespace
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            // Dismisses the keyboard when the user starts browsing
            // results, which a `List` did for free.
            .scrollDismissesKeyboard(.immediately)
        } else if viewModel.errorMessage != nil {
            // The inset banner already explains what happened; don't stack
            // a second, redundant empty state underneath it.
            Color.clear
        } else if !viewModel.searchText.isEmpty && !viewModel.isLoading {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else if viewModel.searchText.isEmpty {
            // The `label:` closure form tints the icon without
            // `.foregroundStyle` also recoloring the title and description.
            // The title string is asserted by a UI test — keep it exact.
            ContentUnavailableView {
                Label {
                    Text("Find a character")
                } icon: {
                    Image(systemName: "circle.hexagongrid.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(PortalTheme.portalGreen)
                }
            } description: {
                Text("Type a name to open an interdimension portal.")
            }
        } else {
            // Mid-search on a previously empty list: the toolbar spinner is
            // the only affordance needed, so keep the space quiet.
            Color.clear
        }
    }
}

/// A dismissible-by-retry error strip. Deliberately not a full-screen
/// `ContentUnavailableView`: a failed refresh shouldn't hide results the
/// user already has, and it shouldn't cost them their typing either.
private struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Retry", action: retry)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        // `.quaternary` is nearly invisible over the artwork.
        .background(.black.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PortalTheme.portalGlow)
                .frame(height: 1)
        }
        // One VoiceOver stop for the message, with Retry still reachable
        // as its own control.
        .accessibilityElement(children: .contain)
    }
}

/// One grid cell: image on top, name and species beneath.
private struct CharacterCell: View {
    let character: Character

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: character.image) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
            }
            // Square cells keep the grid rows aligned regardless of what
            // the source image's proportions are.
            .aspectRatio(1, contentMode: .fit)
            // `.fill` overflows its frame; clip before shaping.
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(character.name)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    // Decorative: the cell's VoiceOver label is unchanged,
                    // and the detail screen spells the status out.
                    Circle()
                        .fill(PortalTheme.color(for: character.status))
                        .frame(width: 6, height: 6)
                    Text(character.species)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // Keeps the text block left-aligned when a short name would
            // otherwise let the VStack shrink below the column width.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(PortalTheme.cardFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(PortalTheme.portalGlow, lineWidth: 1)
        }
        // Combines the cell into a single VoiceOver stop rather than
        // three separate ones (image, name, species). The label stays
        // "<name>, <species>" — a UI test asserts that exact format.
        .accessibilityElement(children: .combine)
        // Stable handle for UI tests. A `LazyVGrid` produces no cells, so
        // there's nothing generic like `app.cells` to query; without this
        // tests would have to match on visible text.
        .accessibilityIdentifier("character-cell")
    }
}

#Preview {
    CharacterListView()
}
