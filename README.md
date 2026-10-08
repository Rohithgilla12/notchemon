# Notchemon

A small creature lives in your MacBook notch. It peeks out from under the notch, wanders along the top of the screen and the Dock, watches your cursor, naps when you step away, and grows when you finish focused work. Hover the notch and it opens into a panel with a focus timer, a quick-note field, and a five-slot file stash.

Notchemon is free, open source, and local. It has no accounts, no telemetry, and no paid tier.

> Pokémon is a trademark of Nintendo, The Pokémon Company, and Game Freak; this is an unaffiliated, free, non-commercial fan work.

## Features

- **A creature in the notch.** On first launch the notch opens and offers four starters, shown as large portraits. The app fetches species data live from [PokéAPI](https://pokeapi.co) and animated sprites from [SpriteCollab](https://github.com/PMDCollab/SpriteCollab), and caches both in `~/Library/Application Support/Notchemon/Cache/`. Later launches work offline. A species or animation that SpriteCollab lacks falls back to PokéAPI's own animated sprite.
- **Behaviour.** The creature fidgets every 5 to 15 seconds. When the cursor is within 150 pt of it, it turns to face it in any of eight directions. It hops when the cursor first comes that close while the notch is closed, at most once every 4 seconds. It strikes a pose when it levels up. After 10 minutes without input it falls asleep where it stands. Under the notch it ducks up into the notch to sleep. Any input wakes it. Under the notch it pops back out, and elsewhere it rests where it woke and then wanders on.
- **Wandering.** While the notch is closed, the creature walks along the strip just below the menu bar. It rests for 4 to 15 seconds, then walks at least 60 pt to a new spot, and sometimes back to the notch. It always stays fully on the screen that has the notch. Clicks anywhere in that strip outside the notch reach the menu bar and apps as usual. The creature goes home during a focus session or when you open the notch, and it stays under the notch over full-screen apps. When the cursor comes within 150 pt of the notch, the creature runs home to greet it.
- **Dock walking.** The creature can also walk along the top of the Dock. After a rest it hops to the Dock or back up about one time in four. A hop fades it out where it stands and fades it in at a random spot on the other side. On the Dock it faces and hops at the cursor from where it stands, and a cursor at the notch does not call it home. Opening the notch or going full screen brings it home at once, a focus session makes it hop up and walk home, and it sleeps on the Dock if it dozes off there. The Dock must be at the bottom of a screen, must not hide automatically, and must leave room to walk. If it moves, starts hiding, or the permission below is turned off, the creature hops up to the top edge. Clicks on the Dock always reach the Dock.
- **Motion settings.** Use the menu bar's Motion submenu to choose how much the creature moves. Changes apply at once and persist.
  - **Calm** (the default): the creature stands still on its idle pose. Each fidget plays its idle animation once.
  - **Lively**: the creature loops its idle animation. For some species, that animation is a hop about once a second.
  - **Sitting**: the creature lies down where its sprite set has a lying pose. Otherwise it stands calm.
  - **Wander** sets where the creature walks. **Top Edge and Dock** (the default) uses the whole width of the screen and the Dock. **Across the Top Edge** uses the whole width of the screen, **Near the Notch** keeps it within 200 pt of the notch, **On the Dock** keeps it on the Dock with visits back to the notch, and **Off** keeps it under the notch.
  - **Allow Dock Walking…** appears when Wander includes the Dock and the app does not have Accessibility permission. See [Permissions](#permissions).
  - **Hop When Cursor Comes Near** and **Fidgets** turn those motions off.
- **Expanding notch.** Hover the notch, or press ⌃⌥N anywhere, and the notch springs open. It closes 0.5 seconds after the cursor leaves. ⌃⌥N toggles it, and Escape closes it while the note field has focus. While the notch is closed, menu-bar icons beside it stay clickable.
- **Focus timer and progression.** Start a focus session from the panel or the menu bar. A thin ring around the notch shows the time left. A completed 25-minute session gives 100 XP, and a session you stop early gives none. Each level needs `level × 40` XP. The creature evolves at the level its evolution data gives, with a white flash. Item, trade, and friendship evolutions never trigger.
- **Quick note.** Type in the panel and press Enter to append `- [YYYY-MM-DD HH:mm] text` to `~/Documents/Notchemon/notes.md`.
- **File stash.** Drop up to five files on the notch, closed or open. The creature holds them as bookmarks, so a stashed file survives a rename or move. Drag an icon out of the panel to drop the file elsewhere, which also removes it from the stash. Click an icon to open the file. When the stash is full, the notch shakes and refuses the drop.
- **Menu bar.** The menu bar item offers start and stop focus, the focus length, the sleep toggle, the virtual notch toggle, the Motion submenu, choose creature (this resets progress, after confirmation), open notes folder, and quit.
- **Macs without a notch.** The app draws a black virtual notch at the top centre of the built-in display, or of the main display in clamshell mode. You can turn this off.

## Permissions

Notchemon never asks for a permission on its own. It reads idle time with `CGEventSource.secondsSinceLastEventType` and watches the cursor with a global `mouseMoved` monitor. Neither needs Accessibility; only keyboard monitors would. The ⌃⌥N hotkey uses Carbon `RegisterEventHotKey`, which also needs no permission.

Dock walking is the one feature that needs Accessibility permission, because only the Accessibility API reports the Dock's exact width. Without it the Dock is not a perch and the creature stays on the top edge. To turn it on:

1. Open the menu bar item, then **Motion**.
2. Choose **Allow Dock Walking…**. The item shows only while Wander includes the Dock and permission is missing.
3. Read the explanation and choose **Continue**. macOS shows its own Accessibility prompt.
4. In **System Settings > Privacy & Security > Accessibility**, turn on Notchemon.

The app notices the change when macOS announces it or the next time the app becomes active, so you do not need to relaunch it. With permission, the app reads only the Dock's frame, and only when an app launches or quits, the displays change, or the creature steps onto or walks along the Dock. It reads the Dock's position and auto-hide settings from the `com.apple.dock` preferences. It never sends input to other apps. To revoke the permission, turn Notchemon off in the same settings pane; the creature then hops back up to the top edge.

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
| `NotchemonDebugSleepSeconds` | Puts the creature to sleep after this many seconds without input, instead of 10 minutes. |
| `NotchemonCreatureProvider` | Set to `original` to use the built-in procedural creatures instead of PokéAPI. See [docs/takedown.md](docs/takedown.md). |

```sh
defaults write com.rohithgilla.Notchemon NotchemonDebugSessionSeconds -float 5
defaults write com.rohithgilla.Notchemon NotchemonDebugSleepSeconds -float 20
defaults write com.rohithgilla.Notchemon NotchemonCreatureProvider original
defaults delete com.rohithgilla.Notchemon NotchemonDebugSessionSeconds
defaults delete com.rohithgilla.Notchemon NotchemonDebugSleepSeconds
```

To start fresh, quit the app and delete `~/Library/Application Support/Notchemon/`.

## Asset guardrail

The repository and the app bundle must never contain creature sprites, cries, names, or data files. `scripts/check-no-assets.sh` fails on any image or audio file. It also fails on any of the default starters' names in the repository or in a built app:

```sh
scripts/check-no-assets.sh .build/dd/Build/Products/Debug/Notchemon.app
```

CI runs this check on every push. All app code talks to the `CreatureProvider` protocol. `CreatureProviderFactory` is the only file that names a concrete provider.

## Release

Releases are Developer ID signed, notarised, and published on GitHub Releases only. To bump the version, edit `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml`. XcodeGen generates `Notchemon/Info.plist` and the entitlements file from it, so neither is tracked. `scripts/release.sh` builds the Release configuration, verifies the signature, zips the app, and notarises and staples it when credentials exist. It then prints the SHA-256 for `Casks/notchemon.rb`. Pushing a `v*` tag runs the same script in CI when the signing and App Store Connect secrets are set.

## Credits

- **Sprites.** Creature sprites come from [SpriteCollab](https://github.com/PMDCollab/SpriteCollab), a community project in which many artists draw sprites in the style of the Mystery Dungeon games. The sprites are licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). The expanded notch names the artists of the sprite on screen, as the licence requires. The app downloads sprites at runtime and never bundles them.
- **Species data and fallback art.** Names, evolution data, portraits, and fallback sprites come from [PokéAPI](https://pokeapi.co), also fetched at runtime.

## License

The code is MIT licensed; see [LICENSE](LICENSE). The licence covers this code only. It grants no rights to any third-party trademark or artwork that the app displays at runtime.
