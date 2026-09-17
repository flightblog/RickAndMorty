import SwiftUI

@main
struct RickAndMortyApp: App {
    var body: some Scene {
        WindowGroup {
            CharacterListView()
                // The search screen's backdrop is a dark space scene.
                // Following the system would put dark text on it in light
                // mode, which would need a second background image and a
                // light variant of every themed color.
                .preferredColorScheme(.dark)
        }
    }
}
