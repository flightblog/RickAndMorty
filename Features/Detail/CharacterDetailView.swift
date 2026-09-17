import SwiftUI

struct CharacterDetailView: View {
    let character: Character

    /// The downloaded image, held so the share sheet can attach the real
    /// picture rather than just its URL. `nil` until the fetch finishes,
    /// or permanently if it fails — in which case sharing degrades to
    /// metadata-only rather than the button doing nothing.
    @State private var shareItem: CharacterShareItem?

    private let imageLoader: ImageLoading

    init(character: Character, imageLoader: ImageLoading = ImageLoader()) {
        self.character = character
        self.imageLoader = imageLoader
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: character.image) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        // Constrained rather than `.resizable()`: a
                        // full-width stretched SF Symbol reads as a
                        // rendering bug, not a placeholder.
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .background(.quaternary)
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Photo of \(character.name)")

                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "Species", value: character.species)
                    DetailRow(
                        label: "Status",
                        value: character.status.rawValue,
                        accent: PortalTheme.color(for: character.status)
                    )
                    DetailRow(label: "Origin", value: character.origin.name)
                    if !character.type.isEmpty {
                        DetailRow(label: "Type", value: character.type)
                    }
                    DetailRow(label: "Created", value: character.formattedCreatedDate)
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                shareButton
            }
        }
        // `AsyncImage` doesn't hand back the bytes it loaded, so the share
        // payload is fetched separately. Both hit the same URL, so the
        // URL cache serves the second request without a second download.
        .task {
            shareItem = await imageLoader.loadShareItem(for: character)
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareItem {
            // Image + metadata: the picture is the shared item, the
            // summary rides along as the message text.
            ShareLink(
                item: shareItem,
                subject: Text(character.name),
                message: Text(character.shareSummary),
                preview: SharePreview(
                    character.name,
                    image: shareItem.previewImage
                )
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } else {
            // Image still loading (or unavailable): share the metadata on
            // its own rather than disabling the button outright, so the
            // feature still works when the picture can't be fetched.
            ShareLink(
                item: character.shareSummary,
                subject: Text(character.name),
                preview: SharePreview(character.name)
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// A label/value pair, styled consistently and readable at any Dynamic
/// Type size since it uses `Text` with system text styles rather than
/// fixed font sizes or fixed-height frames.
private struct DetailRow: View {
    let label: String
    let value: String
    /// When set, draws a small dot beside the value. Only the status
    /// row uses it.
    var accent: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            // An overlay rather than an `HStack`: wrapping the value in
            // another container changes how `children: .combine` flattens
            // the row and stops `app.staticTexts["Species"]` resolving,
            // which a UI test asserts.
            Text(value)
                .font(.body)
                .padding(.leading, accent == nil ? 0 : 14)
                .overlay(alignment: .leading) {
                    if let accent {
                        Circle()
                            .fill(accent)
                            .frame(width: 8, height: 8)
                    }
                }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        CharacterDetailView(
            character: Character(
                id: 1,
                name: "Rick Sanchez",
                status: .alive,
                species: "Human",
                type: "",
                origin: .init(name: "Earth (C-137)"),
                image: URL(string: "https://rickandmortyapi.com/api/character/avatar/1.jpeg")!,
                created: "2017-11-04T18:48:46.250Z"
            )
        )
    }
}
