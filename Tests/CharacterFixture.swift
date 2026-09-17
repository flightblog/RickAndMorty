import Foundation
@testable import RickAndMorty

extension Character {
    /// A stock character for tests, with every field a test varies
    /// exposed as a defaulted parameter. Shared so `CharacterTests` and
    /// `CharacterShareTests` don't each carry their own near-identical
    /// builder.
    static func fixture(
        name: String = "Rick Sanchez",
        type: String = "",
        imageURL: String = "https://rickandmortyapi.com/api/character/avatar/1.jpeg",
        created: String = "2017-11-04T18:48:46.250Z"
    ) -> Character {
        Character(
            id: 1,
            name: name,
            status: .alive,
            species: "Human",
            type: type,
            origin: .init(name: "Earth (C-137)"),
            image: URL(string: imageURL)!,
            created: created
        )
    }
}
