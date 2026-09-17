import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// The character's image plus its metadata, packaged for the share sheet.
///
/// `ShareLink` needs the actual image bytes to offer "Save Image" or to
/// attach a picture to a message; handing it only the remote `URL` would
/// share a link instead. `AsyncImage` doesn't expose the image it loaded,
/// so the detail view fetches the data itself and wraps it here.
struct CharacterShareItem: Transferable {
    let imageData: Data
    let filename: String
    /// The type the server actually returned, so we don't mislabel a PNG
    /// as a JPEG (or vice versa) based on the URL's extension.
    let contentType: UTType

    /// The same bytes as a SwiftUI `Image`, for `SharePreview`'s
    /// thumbnail. `SharePreview` needs a resolved image up front; it
    /// won't render one by going through `transferRepresentation`.
    var previewImage: Image {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: imageData) {
            return Image(uiImage: uiImage)
        }
        #endif
        return Image(systemName: "photo")
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .image) { item in
            item.imageData
        }
        // Gives the receiving app a real filename ("Rick Sanchez.jpeg")
        // rather than a generic one.
        .suggestedFileName { item in
            item.filename
        }
    }
}

extension CharacterShareItem {
    /// - Parameters:
    ///   - data: the raw bytes returned for `character.image`.
    ///   - mimeType: the response's `Content-Type`, when the server sent one.
    init?(character: Character, data: Data, mimeType: String?) {
        // Only share what we can actually identify as an image; a 404 page
        // or an HTML error body must not be handed to the share sheet
        // labelled as a picture.
        let resolved = mimeType.flatMap { UTType(mimeType: $0) }
            ?? UTType(filenameExtension: character.image.pathExtension)
        guard let resolved, resolved.conforms(to: .image) else { return nil }

        let ext = resolved.preferredFilenameExtension
            ?? character.image.pathExtension
        self.imageData = data
        self.filename = "\(character.name).\(ext)"
        self.contentType = resolved
    }
}
