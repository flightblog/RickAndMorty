# Rick and Morty Character Search

[![CI](https://github.com/flightblog/RickAndMorty/actions/workflows/ci.yml/badge.svg)](https://github.com/flightblog/RickAndMorty/actions/workflows/ci.yml)

An iOS app to search characters from the [Rick and Morty API](https://rickandmortyapi.com), built with SwiftUI, async/await, and the MVVM pattern.

## Getting it running

```
open RickAndMorty.xcodeproj
```

Build and run on any iOS 17+ simulator (⌘R). The suite is verified on both iOS 26.5 and iOS 17.4, since the hero-image transition takes a different path on each. No API key, no dependencies, no configuration. Tests run with ⌘U, or:

```
xcodebuild -project RickAndMorty.xcodeproj -scheme RickAndMorty \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Targets: `RickAndMorty` (app), `RickAndMortyTests` (32 unit tests), and `RickAndMortyUITests` (10 UI tests, which exercise the real API end to end). Deployment target is iOS 17.0 — the UI uses `NavigationStack`, `.task(id:)`, and `ContentUnavailableView`.

## CI

`.github/workflows/ci.yml` runs on every push and pull request to `main`, on `macos-15` with Xcode 26.0.1 pinned (the image defaults to 16.4, and the `iPhone 17` simulator needs an iOS 26 runtime).

Two jobs, split deliberately:

- **Unit tests** — the 32 hermetic tests. These gate the build.
- **UI tests (live API)** — the 10 end-to-end tests. These run on pull requests and manual `workflow_dispatch` runs only, not on pushes to `main`: they drive a simulator against the live API and take about four minutes, against roughly ten seconds for the unit suite. They are also marked `continue-on-error`, because they depend on `rickandmortyapi.com` being up: a red X here can mean the API is slow, not that the app regressed. The job pings the API first and emits a warning annotation if it is unreachable, so the logs distinguish the two cases. Check it before assuming a regression.

## Architecture

**MVVM**, no third-party dependencies. The API surface here is small enough that adding a networking library or DI framework would be over-engineering; `URLSession` + `async/await` covers it cleanly.

- **Models/** — `Codable` structs mirroring the parts of the API's JSON the app actually uses (`Character`, `CharacterResponse`) — the response's `info` pagination block is omitted, since nothing reads it and `Decodable` ignores unknown keys. `Character.Status` degrades unknown values to `.unknown` instead of failing to decode, since new status values shouldn't crash the app.
- **Networking/APIClient.swift** — one client, one method (`searchCharacters(named:)`). Built against a `URLSessionProtocol` rather than `URLSession` directly so tests can inject a fake and never touch the network. Deliberately *not* a singleton: it's injected into the ViewModel, which is what makes the tests possible.
- **Features/Search/** — `CharacterListViewModel` (`@MainActor`, `ObservableObject`) owns `searchText`, `characters`, `isLoading`, `errorMessage`. `CharacterListView` drives it via `.task(id: searchText)`, which SwiftUI automatically cancels and restarts whenever the text changes — that's what gives us "search updates on every keystroke" without ever racing a stale response against a fresh one. Results render in a `LazyVGrid`. Before the first search, the screen shows a custom `ContentUnavailableView` ("Find a character") rather than an empty grid; it uses the `label:` closure form so tinting the portal icon doesn't also recolor the title and description. A no-match search falls through to `ContentUnavailableView.search(text:)` instead, so "nothing yet" and "nothing found" read differently.
- **Features/Detail/** — the detail screen; `type` only renders when non-empty per the spec. `CharacterShareItem` + `ImageLoader` back the share button.
- **Features/Theme/** — `PortalTheme` holds the palette and `PortalBackground` wraps the space artwork, so the theming isn't color literals scattered through the views.

## What I'd add with more time

- Status/species/type filters (`Menu` + extra query items on the same endpoint).
- An on-disk or `NSCache`-backed image cache instead of relying on `AsyncImage`'s per-view caching.
- Pinning the search bar to the top on iOS 26 (see below).

## One thing to know before running it

On **iOS 26**, `.searchable` renders the search field at the *bottom* of the screen and collapses the navigation bar while a search is active — so the "Rick and Morty" title is visible at launch but hidden while typing. That's the current platform default, not a layout bug; on iOS 17–18 the field sits under the title as the spec describes. Pinning it to the top is a one-line change (`.searchToolbarBehavior(.minimize)`, iOS 26+), but it changes the look on the newest OS, so I left the platform default in place rather than guess at the preference.
