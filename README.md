# Notchemon

A small creature lives in your MacBook notch. It peeks out from under the notch, watches your cursor, naps when you step away, and grows when you finish focused work. Hover the notch and it opens into a panel with a focus timer, a quick-note field, and a five-slot file stash.

Notchemon is free, open source, and local. It has no accounts, no telemetry, and no paid tier.

> Pokémon is a trademark of Nintendo, The Pokémon Company, and Game Freak; this is an unaffiliated, free, non-commercial fan work.

## Features

- **A creature in the notch.** On first launch the notch opens and offers four starters. The app fetches their names and sprites live from [PokéAPI](https://pokeapi.co) and caches them in `~/Library/Application Support/Notchemon/Cache/`. Later launches work offline.
- **Behaviour.** The creature fidgets every 5 to 15 seconds and looks towards the cursor when it is within 150 pt. It hops when the cursor enters the notch. After 10 minutes without input it ducks up into the notch to sleep, and any input brings it back out.
- **Expanding notch.** Hover the notch, or press ⌃⌥N anywhere, and the notch springs open. It closes 0.5 seconds after the cursor leaves. ⌃⌥N toggles it, and Escape closes it while the note field has focus. While the notch is closed, menu-bar icons beside it stay clickable.
- **Focus timer and progression.** Start a focus session from the panel or the menu bar. A thin ring around the notch shows the time left. A completed 25-minute session gives 100 XP, and a session you stop early gives none. Each level needs `level × 40` XP. The creature evolves at the level its evolution data gives, with a white flash. Item, trade, and friendship evolutions never trigger.
- **Quick note.** Type in the panel and press Enter to append `- [YYYY-MM-DD HH:mm] text` to `~/Documents/Notchemon/notes.md`.
- **File stash.** Drop up to five files on the notch, closed or open. The creature holds them as security-scoped bookmarks. Drag an icon out of the panel to drop the file elsewhere, which also removes it from the stash. Click an icon to open the file. When the stash is full, the notch shakes and refuses the drop.
- **Menu bar.** The menu bar item offers start and stop focus, the focus length, the sleep toggle, the virtual notch toggle, choose creature (this resets progress, after confirmation), open notes folder, and quit.
- **Macs without a notch.** The app draws a black virtual notch at the top centre of the built-in display, or of the main display in clamshell mode. You can turn this off.

## Permissions

Notchemon asks for no permissions. It reads idle time with `CGEventSource.secondsSinceLastEventType` and watches the cursor with a global `mouseMoved` monitor. Neither needs Accessibility; only keyboard monitors would. The ⌃⌥N hotkey uses Carbon `RegisterEventHotKey`, which also needs no permission.

## Build

Requirements: macOS 14 or later, Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated and is not committed.

```sh
xcodegen generate
xcodebuild test -project Notchemon.xcodeproj -scheme Notchemon -destination 'platform=macOS' -derivedDataPath .build/dd
open .build/dd/Build/Products/Debug/Notchemon.app
```

Debug builds are signed ad hoc, so they need no certificate.

### Debug defaults

| Default | Effect |
| --- | --- |
| `NotchemonDebugSessionSeconds` | Shortens every focus session to this many seconds. Each session still credits the configured length, so 44 short sessions take a fresh starter from level 5 to level 16. |
| `NotchemonCreatureProvider` | Set to `original` to use the built-in procedural creatures instead of PokéAPI. See [docs/takedown.md](docs/takedown.md). |

```sh
defaults write com.rohithgilla.Notchemon NotchemonDebugSessionSeconds -float 5
defaults write com.rohithgilla.Notchemon NotchemonCreatureProvider original
defaults delete com.rohithgilla.Notchemon NotchemonDebugSessionSeconds
```

To start fresh, quit the app and delete `~/Library/Application Support/Notchemon/`.

## Asset guardrail

The repository and the app bundle must never contain creature sprites, cries, names, or data files. `scripts/check-no-assets.sh` fails on any image or audio file. It also fails on any of the default starters' names in the repository or in a built app:

```sh
scripts/check-no-assets.sh .build/dd/Build/Products/Debug/Notchemon.app
```

CI runs this check on every push. All app code talks to the `CreatureProvider` protocol. `CreatureProviderFactory` is the only file that names a concrete provider.

## Release

Releases are Developer ID signed, notarised, and published on GitHub Releases only. `scripts/release.sh` builds the Release configuration, verifies the signature, zips the app, and notarises and staples it when credentials exist. It then prints the SHA-256 for `Casks/notchemon.rb`. Pushing a `v*` tag runs the same script in CI when the signing and App Store Connect secrets are set.

## License

The code is MIT licensed; see [LICENSE](LICENSE). The licence covers this code only. It grants no rights to any third-party trademark or artwork that the app displays at runtime.
