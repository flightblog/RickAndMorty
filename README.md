# Rick and Morty Character Search

An iOS app to search characters from the [Rick and Morty API](https://rickandmortyapi.com), built with SwiftUI, async/await, and the MVVM pattern.

## Getting it running

```
open RickAndMorty.xcodeproj
```

Build and run on any iOS 17+ simulator (⌘R). The suite is verified on both iOS 26.5 and iOS 17.4, since the hero-image transition takes a different path on each (see below). No API key, no dependencies, no configuration. Tests run with ⌘U, or:

```
xcodebuild -project RickAndMorty.xcodeproj -scheme RickAndMorty \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Targets: `RickAndMorty` (app), `RickAndMortyTests` (32 unit tests), and `RickAndMortyUITests` (10 UI tests, which exercise the real API end to end). Deployment target is iOS 17.0 — the UI uses `NavigationStack`, `.task(id:)`, and `ContentUnavailableView`.

## Architecture

**MVVM**, no third-party dependencies. The API surface here is small enough that adding a networking library or DI framework would be over-engineering; `URLSession` + `async/await` covers it cleanly.

- **Models/** — `Codable` structs mirroring the parts of the API's JSON the app actually uses (`Character`, `CharacterResponse`) — the response's `info` pagination block is omitted, since nothing reads it and `Decodable` ignores unknown keys. `Character.Status` degrades unknown values to `.unknown` instead of failing to decode, since new status values shouldn't crash the app.
- **Networking/APIClient.swift** — one client, one method (`searchCharacters(named:)`). Built against a `URLSessionProtocol` rather than `URLSession` directly so tests can inject a fake and never touch the network. Deliberately *not* a singleton: it's injected into the ViewModel, which is what makes the tests possible.
- **Features/Search/** — `CharacterListViewModel` (`@MainActor`, `ObservableObject`) owns `searchText`, `characters`, `isLoading`, `errorMessage`. `CharacterListView` drives it via `.task(id: searchText)`, which SwiftUI automatically cancels and restarts whenever the text changes — that's what gives us "search updates on every keystroke" without ever racing a stale response against a fresh one. Results render in a `LazyVGrid`.
- **Features/Detail/** — the detail screen; `type` only renders when non-empty per the spec. `CharacterShareItem` + `ImageLoader` back the share button.
- **Features/Theme/** — `PortalTheme` holds the palette and `PortalBackground` wraps the space artwork, so the theming isn't color literals scattered through the views.

## Design decisions worth flagging in review

- **Debounce + cancellation**: `search(for:)` sets `isLoading` *first*, then `Task.sleep`s for a 300ms debounce, then checks `Task.isCancelled` before and after the network call. The ordering matters: the view re-runs this method on every keystroke via `.task(id:)`, so setting the flag after the sleep would mean the spinner never appeared while the user was actively typing — each keystroke cancels the previous task mid-sleep. `isLoading` is cleared in a `defer` so a cancelled task can't strand the spinner on. Both behaviors have regression tests.
- **Date parsing**: the API's `created` values carry fractional seconds (`2017-11-04T18:48:46.250Z`), which `ISO8601DateFormatter` does **not** parse under its default options — it needs an explicit `.withFractionalSeconds`. The formatter is held `static` because `createdDate` is read during list rendering and formatter init is expensive.
- **Main thread safety**: the ViewModel is `@MainActor`, so every `@Published` write is guaranteed on the main thread (required for SwiftUI), while the actual `URLSession` call happens off it — nothing here can block the UI thread.
- **Error handling**: `APIError` is a small typed enum. A 404 from a no-match search is deliberately mapped to `.noResults` and treated as an empty state in the UI, not a failure banner — that's the correct read of the API's actual behavior, not a generic "any non-2xx is an error" catch-all. A real failure shows an inline banner with a **Retry** button that re-runs the last query (skipping the debounce, since it's an explicit action) and leaves any results already on screen intact — a transient network blip shouldn't cost the user their typing or their list.
- **Sharing (extra credit)**: a `ShareLink` in the detail toolbar shares the image *and* the metadata. The wrinkle is that `AsyncImage` never hands back the bytes it loaded, so passing it to `ShareLink` would share a URL rather than a picture — the sheet would offer "Add to Reading List" instead of "Save Image". `ImageLoader` therefore fetches the image separately into a `Transferable` (`CharacterShareItem`); both requests hit the same URL, so `URLSession`'s cache serves the second one without a second download. The content type comes from the response's `Content-Type` rather than the URL's extension, so a PNG served from a `.jpeg` path isn't mislabelled, and a non-image body (an HTML error page) is rejected instead of being shared as a picture. If the fetch fails, the button degrades to sharing the metadata text alone rather than going dead.
- **Grid layout**: results are a `LazyVGrid` with `GridItem(.adaptive(minimum: 150))` rather than a fixed column count, so the same code gives 2 columns on a phone in portrait and 4 in landscape (there's a UI test asserting exactly that), more on an iPad, and collapses to 1 when a large Dynamic Type size widens the cells. Cells are forced square with `.aspectRatio(1, contentMode: .fit)` so rows stay aligned no matter what proportions the source images have. Two things a `List` gave for free had to be restored by hand: `.buttonStyle(.plain)`, or every cell renders in the accent color because `NavigationLink` styles its label as a button, and `.scrollDismissesKeyboard(.immediately)`.
- **Hero image transition (extra credit)**: tapping a cell zooms its image up into the detail view rather than sliding the whole screen in, via `matchedTransitionSource(id:in:)` on the cell and `navigationTransition(.zoom(sourceID:in:))` on the destination, keyed by `character.id` so each cell animates from its own rect. Both APIs are iOS 18+, and this app targets iOS 17 — `ZoomTransition.swift` wraps them in `@ViewBuilder` shims with `if #available`, so the call sites stay readable as plain modifiers and iOS 17 silently keeps the standard push. I ran the full suite against an iOS 17.4 simulator as well as iOS 26 to confirm the fallback isn't just a compile-time guard.
- **URL construction**: user input goes through `URLComponents`/`URLQueryItem`, never raw string interpolation, so special characters in a search term can't produce a malformed or unsafe URL.
- **Testability**: `URLSessionProtocol` + `MockURLSession` let every test run fully offline and deterministically (debounce is set to 0ms where the test isn't specifically exercising it). `MockURLSession` records the URLs it was asked for, so tests can assert that an empty query makes no request at all and that search text is correctly percent-encoded into the `name` query item. The grid cells carry an `.accessibilityIdentifier` because a `LazyVGrid` emits no `cells` for `XCUITest` to query — each cell surfaces as a button, so matching on an identifier beats matching on position (the on-screen keyboard contributes buttons of its own).
- **Theming**: a space backdrop on the search screen, portal green as the accent, translucent grid cards, and a status dot on each cell and the detail screen's Status row. The app is pinned to `.preferredColorScheme(.dark)`, since following the system would put dark text on a dark backdrop in light mode — supporting both means a second background image and a light variant of every themed color. The dot is never the only signal: the status text sits beside it and the VoiceOver labels are unchanged.
- **Two things the theming turned up**: hiding the navigation bar's material, so the artwork runs under it, exposed the glass capsule iOS 26 draws behind every toolbar item — the always-present spinner is hidden with `.opacity(0)`, which fades the spinner but not the capsule, leaving a stray dark circle. `sharedBackgroundVisibility(.hidden)` (iOS 26+, shimmed in `ZoomTransition.swift` like the zoom APIs) hides it. Separately, giving the Status row its dot via an `HStack` changed how `.accessibilityElement(children: .combine)` flattens the row, so `app.staticTexts["Species"]` stopped resolving and a UI test failed. It's an `.overlay` on the existing `Text` now, which adds no sibling to the layout tree.
- **Accessibility**: rows and detail fields use `.accessibilityElement(children: .combine)` so VoiceOver reads each row/field as one coherent stop; all text uses system text styles (`.headline`, `.body`, `.caption`) rather than fixed sizes, so Dynamic Type works without extra code.

## What I'd add with more time

- Status/species/type filters (`Menu` + extra query items on the same endpoint).
- An on-disk or `NSCache`-backed image cache instead of relying on `AsyncImage`'s per-view caching.
- Pinning the search bar to the top on iOS 26 (see below).

## One thing to know before running it

On **iOS 26**, `.searchable` renders the search field at the *bottom* of the screen and collapses the navigation bar while a search is active — so the "Characters" title is visible at launch but hidden while typing. That's the current platform default, not a layout bug; on iOS 17–18 the field sits under the title as the spec describes. Pinning it to the top is a one-line change (`.searchToolbarBehavior(.minimize)`, iOS 26+), but it changes the look on the newest OS, so I left the platform default in place rather than guess at the preference.
