# Notchemon

A small creature lives in your MacBook notch. It peeks out from under the notch, wanders along the top of the screen and the Dock, watches your cursor, naps when you step away, and grows when you finish focused work. Hover the notch and it opens into a panel with a focus timer, a quick-note field, and a five-slot file stash.

Notchemon is free, open source, and local. It has no accounts, no telemetry, and no paid tier.

> Pokémon is a trademark of Nintendo, The Pokémon Company, and Game Freak; this is an unaffiliated, free, non-commercial fan work.

## Features

- **A creature in the notch.** On first launch the notch opens and offers four starters, shown as large portraits. The app fetches species data live from [PokéAPI](https://pokeapi.co) and animated sprites from [SpriteCollab](https://github.com/PMDCollab/SpriteCollab), and caches both in `~/Library/Application Support/Notchemon/Cache/`. Later launches work offline. A species or animation that SpriteCollab lacks falls back to PokéAPI's own animated sprite.
- **Behaviour.** The creature fidgets every 5 to 15 seconds. When the cursor is within 150 pt of it, it turns to face it in any of eight directions. It hops when the cursor first comes that close while the notch is closed, at most once every 4 seconds. It strikes a pose when it levels up. After 10 minutes without input it falls asleep where it stands. Under the notch it ducks up into the notch to sleep. Any input wakes it. Under the notch it pops back out, and elsewhere it rests where it woke and then wanders on.
- **Wandering.** While the notch is closed, the creature walks along the strip just below the menu bar. It rests for 4 to 15 seconds, then walks at least 60 pt to a new spot, and sometimes back to the notch. It always stays fully on the screen that has the notch. Clicks anywhere in that strip outside the notch reach the menu bar and apps as usual. The creature goes home during a focus session or when you open the notch, and it stays under the notch over full-screen apps. When the cursor comes within 150 pt of the notch, the creature runs home to greet it.
- **Dock walking.** The creature can also walk along the top of the Dock. After a rest it hops to the Dock or back up about one time in four. A hop fades it out where it stands and fades it in at a random spot on the other side. On the Dock it faces and hops at the cursor from where it stands, and a cursor at the notch does not call it home. Opening the notch or going full screen brings it home at once, a focus session makes it hop up and walk home, and it sleeps on the Dock if it dozes off there. The Dock must be at the bottom of a screen and leave room to walk. If it moves to a side or the permission below is turned off, the creature hops up to the top edge. Clicks on the Dock always reach the Dock.
- **Auto-hiding Dock.** When the Dock hides automatically, the creature walks along the bottom edge of the screen, nearly the full width. When the Dock slides up, a creature above it rises onto the Dock's top edge. A creature beside the Dock stays on the bottom edge. When the Dock hides again, the creature drops back down. If it walks off the end of the shown Dock, it drops down, and if it walks onto the Dock, it climbs up. The app learns that the Dock has slid from the cursor. When the cursor reaches the bottom of the screen or leaves the shown Dock, the app reads the Dock a moment later, so the creature moves a fraction of a second after the Dock does.
- **Motion settings.** Use the menu bar's Motion submenu to choose how much the creature moves. Changes apply at once and persist.
  - **Calm** (the default): the creature stands still on its idle pose. Each fidget plays its idle animation once.
  - **Lively**: the creature loops its idle animation. For some species, that animation is a hop about once a second.
  - **Sitting**: the creature lies down where its sprite set has a lying pose. Otherwise it stands calm.
  - **Wander** sets where the creature walks. **Top Edge and Dock** (the default) uses the whole width of the screen and the Dock. If an earlier build saved a Wander choice, that choice stays; the default applies only where none is saved, as on a new install. **Across the Top Edge** uses the whole width of the screen, **Near the Notch** keeps it within 200 pt of the notch, **On the Dock** keeps it on the Dock with visits back to the notch, and **Off** keeps it under the notch.
  - **Allow Dock Walking…** appears when Wander includes the Dock and the app does not have Accessibility permission. See [Permissions](#permissions).
  - **Hop When Cursor Comes Near** and **Fidgets** turn those motions off.
- **Expanding notch.** Hover the notch, or press ⌃⌥N anywhere, and the notch springs open. It closes 0.5 seconds after the cursor leaves. ⌃⌥N toggles it, and Escape closes it while the note field has focus. While the notch is closed, menu-bar icons beside it stay clickable.
- **Click to Open.** Turn on Click to Open in the menu bar menu, and the notch opens on a click instead of on hover. It stays open wherever the cursor goes. A click on the notch or on empty panel space closes it, and so does ⌃⌥N. Clicks on the panel's controls never close it.
- **Focus timer and progression.** Start a focus session from the panel or the menu bar. A thin ring around the notch shows the time left. A completed 25-minute session gives 100 XP, and a session you stop early gives none. Each level needs `level × 40` XP. The creature evolves at the level its evolution data gives, with a white flash. Item, trade, and friendship evolutions never trigger. The Focus Sound menu plays a chime, a fanfare, or a ping when a session completes, and is off by default.
- **Collection.** Every creature you choose joins your collection and keeps its own stage, level, and XP. Choose **Partners…** in the menu bar to open the notch on your partners, each with its level. Click one to send it out instead. The starters you do not have yet are listed after them; clicking one adds it at level 5. Focus XP goes to the partner that is out, and each partner evolves on its own. Hover a partner to see how far it has walked at its own scale. Stats stay shared across the collection.
- **Walking party.** Up to two more partners can walk along with the one that is out. In **Partners…**, tick **Walking** under a partner to bring it along. The partner that is out shows **Leading** and always walks. With two already walking, ticking a third is refused with a hint to stop one first. The choice is saved with the collection.
  - Each walker wanders the top edge and the Dock on its own, with its own rests, walks, and hops between perches. When a walker picks where to go next, it keeps at least 60 pt from where the others stand and are heading. If no spot is clear, it rests where it is.
  - The leader behaves as a lone creature does. It is the one in the open panel, it earns the focus XP, and it is the one that goes home for the open panel, a focus session, or a cursor at the notch.
  - Followers keep wandering while the panel is open or a session runs, and they never take the leader's place under the notch. Each faces the cursor and hops at it from its own spot.
  - Everyone falls asleep together where they stand. Everyone leaves full screen, and the Dock when it goes, as the leader does. Wander set to **Off** keeps the followers in. A wild creature keeps clear of every walker, and every walker stops to watch it.
  - Each walker's distance, hops, and Dock trips add to the shared stats and to its own distance, measured at its own height. Each walker's moves are logged at debug level under category `roam`:

  ```sh
  log stream --debug --predicate 'subsystem == "com.rohithgilla.Notchemon" && category == "roam"'
  ```
- **Unlocks.** More species become available as you focus and as your creature walks. Tier 0 is the four starters. Each later tier is the three starters of a later generation, in their first stage. A tier opens at a focus total or a creature-scale walking total, whichever you reach first. The open panel then shows **New partners available**, and the picker lists the new species. An open tier only makes its species available. You still add them one at a time, each at level 5. The picker's last line says what opens the next tier.

  | Tier | Focus minutes | Or creature-scale km |
  | --- | --- | --- |
  | 1 | 250 | 15 |
  | 2 | 600 | 35 |
  | 3 | 1,200 | 70 |
  | 4 | 2,000 | 120 |
  | 5 | 3,000 | 180 |
  | 6 | 4,200 | 250 |
  | 7 | 5,600 | 340 |
  | 8 | 7,200 | 440 |

  Unlocks are worked out from the stats each time and never stored, so nothing can fall out of step with them.
- **Wild creatures.** Now and then a wild creature drops in. It walks the Dock when Dock walking is on and your partner is not there, and otherwise the top edge, clear of your partner and of the notch. Your partner stops where it is to watch. Click the wild creature to catch it. It sparkles, shrinks away, and joins your collection in its first stage at level 5, without replacing the partner that is out. If its family is already in your collection, it counts as seen again. Leave it alone and after about a minute it wanders to the end of its walk and hops away. Visits come only while you are using the Mac: input in the last two minutes, not asleep, not in full screen, and not in a focus session. They come about every 45 to 90 minutes of that use, and at most four times a day. Clicks reach the menu bar and the Dock as usual everywhere except on the wild creature itself. The Stats submenu does not show encounters yet; `state.json` counts them under `stats`. Visits, catches, and departures are logged under category `encounter`:

  ```sh
  log show --info --last 1d --predicate 'subsystem == "com.rohithgilla.Notchemon" && category == "encounter"'
  ```
- **Stats.** The menu bar's Stats submenu keeps a tally of your time together: how far the creature has walked, its hops and naps, its trips to the Dock, your focus sessions and minutes, its evolutions, and how many days you have been together. Distance reads two ways. **Creature-scale** treats one body height on screen as the species' real height, so a 0.4 m creature drawn 40 pt tall covers 1 cm per point. **On screen** is how far the sprite really moved across the glass, from the display's physical size. Stats count only when something ends, such as a walk, a hop to the Dock, or a nap, so they cost nothing between. Each counted event is logged at debug level under category `stats`:

  ```sh
  log stream --debug --predicate 'subsystem == "com.rohithgilla.Notchemon" && category == "stats"'
  ```
- **Quick note.** Type in the panel and press Enter to append `- [YYYY-MM-DD HH:mm] text` to `~/Documents/Notchemon/notes.md`.
- **System stats.** The open panel shows CPU load, memory in use, free disk space, and, on a Mac with a battery, its charge. It samples every 2 seconds only while the panel is open.
- **File stash.** Drop up to five files on the notch, closed or open. The creature holds them as bookmarks, so a stashed file survives a rename or move. Drag an icon out of the panel to drop the file elsewhere, which also removes it from the stash. Click an icon to open the file. When the stash is full, the notch shakes and refuses the drop.
- **Removing from the stash.** Hover an icon and click its × badge, or right-click it and choose Remove from Stash. The context menu also has Open, Reveal in Finder, and Copy Path. Clear Stash, in the panel and in the menu-bar menu, empties the stash. For 5 seconds after, the panel banner and the menu-bar menu both offer Undo. Removing never moves, deletes, or trashes the file.
- **Menu bar.** The menu bar item offers the Stats submenu, start and stop focus, the focus length, the sleep toggle, the virtual notch toggle, the Motion submenu, floating notes, Partners…, open notes folder, and quit.
- **Macs without a notch.** The app draws a black virtual notch at the top centre of the built-in display, or of the main display in clamshell mode. You can turn this off.

## Permissions

Notchemon never asks for a permission on its own. It reads idle time with `CGEventSource.secondsSinceLastEventType` and watches the cursor with a global `mouseMoved` monitor. Neither needs Accessibility; only keyboard monitors would. The ⌃⌥N hotkey uses Carbon `RegisterEventHotKey`, which also needs no permission.

Dock walking is the one feature that needs Accessibility permission, because only the Accessibility API reports the Dock's exact width. Without it the Dock is not a perch and the creature stays on the top edge. To turn it on:

1. Open the menu bar item, then **Motion**.
2. Choose **Allow Dock Walking…**. The item shows only while Wander includes the Dock and permission is missing.
3. Read the explanation and choose **Continue**. macOS shows its own Accessibility prompt.
4. In **System Settings > Privacy & Security > Accessibility**, turn on Notchemon.

The app checks for the grant every 2 seconds for the next two minutes, then every 30 seconds while Dock walking is wanted and the permission is missing, so you do not need to relaunch it. Each check also tries a real read of the Dock, because `AXIsProcessTrusted` can keep saying no inside a running process after the grant; a read that succeeds counts as granted. The checks and their results are logged, so `log show --info --last 5m --predicate 'subsystem == "com.rohithgilla.Notchemon"'` shows what the app saw. The **Motion** submenu shows a **Dock walking** status line that says whether it is on, needs Accessibility, or is off because the Dock is on the side or a full-screen app is in front. With permission, the app reads only the Dock's frame, and only when an app launches or quits, the displays change, the creature steps onto or walks along the Dock, or, for an auto-hiding Dock, the cursor reaches the bottom of the screen or leaves the shown Dock. It reads the Dock's position and auto-hide settings from the `com.apple.dock` preferences. It never sends input to other apps. To revoke the permission, turn Notchemon off in the same settings pane; the creature then hops back up to the top edge.

### Dock walking doesn't start

If **System Settings > Privacy & Security > Accessibility** shows Notchemon on but the status line still says **needs Accessibility**, the grant belongs to a different build. macOS ties an Accessibility grant to the signature of the build that was granted, so a grant to a development build or an older release does not apply to the one you run now. Choose **Accessibility shows it on but it still won't walk?** in the **Motion** submenu for the steps, or do it by hand:

1. In the Accessibility pane, select Notchemon and remove it with the **−** button.
2. Choose **Allow Dock Walking…** again and turn Notchemon on when macOS asks.

Or reset the grant from Terminal, then allow it again:

```sh
tccutil reset Accessibility com.rohithgilla.Notchemon
```

The app never runs `tccutil` or changes a setting itself.

## Updates, login, and About

- **Updates.** Notchemon updates itself with [Sparkle](https://sparkle-project.org). On the second launch, Sparkle asks whether to check for updates automatically. **Check for Updates…** in the menu checks at any time. Each update is signed with an EdDSA key, and the app checks that signature before it unpacks the update.
- **Launch at Login.** Off by default. Turn it on from the menu. If you turn it off in System Settings › General › Login Items, the menu offers to open that pane, because only System Settings can turn it back on.
- **About Notchemon.** Shows the version, the licence, the disclaimer, and the credits.

## Floating notes

Press ⌃⌥⌘N anywhere, or choose **Floating Notes** in the menu, to open a small translucent notes window. It floats above other windows on every Space and beside full-screen apps, and the cursor lands at the end of the note you last had open. Press ⌃⌥⌘N again or Escape to hide it. Like ⌃⌥N, the hotkey uses Carbon and needs no permission.

- **Notes are Markdown files.** Each note is one file in `~/Documents/Notchemon/Notes/`, and its first line is the title. The file gets its name, `YYYYMMDD-title.md`, at the first save. A new note saves once you end its title line, or after 3 seconds without typing. Renaming the title later keeps the file name, so the note stays easy to find in Finder and other editors. The quick-note log, `~/Documents/Notchemon/notes.md`, is separate and the window never opens it.
- **Saving.** Notes save 0.5 seconds after you stop typing, and when the window hides, loses focus, or the app quits. Every write is atomic.
- **Quitting with unsaved notes.** If a note cannot be saved at quit, for example because the disk is full or the folder is missing, the app stays open. It shows the notes window and an alert that names each note and the error. **Try Again** saves again and quits if that works. **Save a Copy…** asks where to save each note, then quits. **Quit Anyway** quits and loses the unsaved changes. A save that takes more than 5 seconds counts as failed. At logout, restart, or shutdown the same alert appears, and macOS waits for your answer.
- **Edits in other editors.** While the window is open, it checks the folder every 2 seconds. A note without unsaved edits reloads. If the file changed while you had unsaved edits, your text is saved as a new `…-conflict.md` note and stays open, and the original file keeps the other editor's text. A file deleted elsewhere leaves the list, unless you were editing it; then your text is written back.
- **Live Markdown.** Headings, bold, italic, strikethrough, inline code, links, bullets, numbered lists, quotes, rules, and `- [ ]` and `- [x]` tasks are styled as you type. Markup such as `**` and `# ` is hidden except on the line holding the cursor, where it shows faintly. Bullets show as dots and tasks as boxes; click a box to tick it. The file on disk stays plain Markdown. Pasted text arrives as plain text. **Monospaced Font** is in the ⋯ menu.
- **Slash menu.** Type `/` at the start of a line or after a space to add a heading, bold, italic, strikethrough, code, a checklist, a bulleted or numbered list, a quote, or a divider. Keep typing to filter, use the arrow keys to choose, and press Return or Tab to apply. Escape closes the menu.
- **Window.** Drag the title strip to move the window and drag an edge to resize it. The search, new note, pin, and ⋯ buttons appear while the pointer is over the title strip. It opens on the display under the pointer and remembers its frame on each display. **Keep on Top**, the pin, is on by default.

| Shortcut | Action |
| --- | --- |
| ⌘N | New note. |
| ⌘P or ⌘K | Quick switcher. Titles match fuzzily, and note text matches when it holds every word you type. Arrow keys move, Return opens, and Escape closes. |
| ⌘[ and ⌘] | Previous and next note. |
| ⌘⌫ | Move the note to the Trash, after a confirmation. |
| Escape | Hide the window. |

The quick-note field in the notch panel has a small window button. It opens floating notes and turns any text you typed into a new note.

To try floating notes against a scratch folder, set `NotchemonNotesFolder`:

```sh
defaults write com.rohithgilla.Notchemon NotchemonNotesFolder /tmp/notchemon-notes
defaults delete com.rohithgilla.Notchemon NotchemonNotesFolder
```

## Build

Requirements: macOS 14 or later, Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated and is not committed.

```sh
xcodegen generate
xcodebuild test -project Notchemon.xcodeproj -scheme Notchemon -destination 'platform=macOS' -derivedDataPath .build/dd
open .build/dd/Build/Products/Debug/Notchemon.app
```

Debug builds are signed ad hoc, so they need no certificate. They are a separate app to macOS: bundle ID `com.rohithgilla.Notchemon.debug`, display name "Notchemon Debug", defaults domain `com.rohithgilla.Notchemon.debug`, and state under `~/Library/Application Support/Notchemon Debug/`. An Accessibility grant to a Debug build never attaches to the installed app, and the two never share `state.json`. Floating notes still use `~/Documents/Notchemon/`, so set `NotchemonNotesFolder` in the Debug domain before trying notes against a Debug build. Release builds keep `com.rohithgilla.Notchemon`.

### Debug defaults

| Default | Effect |
| --- | --- |
| `NotchemonDebugSessionSeconds` | Shortens every focus session to this many seconds. Each session still credits the configured length, so 44 short sessions take a fresh starter from level 5 to level 16. |
| `NotchemonDebugSleepSeconds` | Puts the creature to sleep after this many seconds without input, instead of 10 minutes. |
| `NotchemonCreatureProvider` | Set to `original` to use the built-in procedural creatures instead of PokéAPI. See [docs/takedown.md](docs/takedown.md). |

| `NotchemonUnlockAll` | Set to `YES` to make every species available: every tier opens, and the Partners picker gets a search field that finds any species by name or number. Set to `NO` in a Debug build to see the real unlock flow. |

A Debug build reads the `com.rohithgilla.Notchemon.debug` domain. Use `com.rohithgilla.Notchemon` for the installed release build.

```sh
defaults write com.rohithgilla.Notchemon.debug NotchemonDebugSessionSeconds -float 5
defaults write com.rohithgilla.Notchemon.debug NotchemonDebugSleepSeconds -float 20
defaults write com.rohithgilla.Notchemon.debug NotchemonCreatureProvider original
defaults delete com.rohithgilla.Notchemon.debug NotchemonDebugSessionSeconds
defaults delete com.rohithgilla.Notchemon.debug NotchemonDebugSleepSeconds
```

The first time a version with the collection loads a state saved before it, it copies that file to `state.v1.backup.json` beside it, once, before saving anything in the new format.

### Developer access

Debug builds start with every species available and add a **Developer** submenu to the menu-bar menu:

- **Unlock All** turns the override on or off. It writes `NotchemonUnlockAll` in the Debug domain.
- **Spawn Encounter Now** brings a wild creature at once. It does not count toward the day's four.
- **Add 1 km** folds a walk of one kilometre at the current partner's scale into the stats.
- **Add 1 Focus Hour** folds a 60-minute focus session into the stats. It gives no XP.
- **Reset Collection…** removes every partner after a confirmation and keeps the stats.

A release build honours the same override from Terminal:

```sh
defaults write com.rohithgilla.Notchemon NotchemonUnlockAll -bool YES
defaults delete com.rohithgilla.Notchemon NotchemonUnlockAll
```

With the override on, type a name or a number in the Partners search field, for example `658`, and click the result to add it at level 5. A later stage joins as itself, and its family counts as one partner.

To start fresh, quit the app and delete `~/Library/Application Support/Notchemon Debug/` for a Debug build, or `~/Library/Application Support/Notchemon/` for the installed one.

## Asset guardrail

The repository and the app bundle must never contain creature sprites, cries, names, or data files. `scripts/check-no-assets.sh` fails on any image or audio file. It also fails on any of the default starters' names in the repository or in a built app. It fails on the franchise's own names too, so the code and the UI stay creature-neutral and the original-creature provider can replace the content. The `allowed_names` list in the script admits only the disclaimer above, the data source's name, and its endpoint paths, each in the files that need them, and the check prints every hit it allows:

```sh
scripts/check-no-assets.sh .build/dd/Build/Products/Debug/Notchemon.app
```

CI runs this check on every push. All app code talks to the `CreatureProvider` protocol. `CreatureProviderFactory` is the only file that names a concrete provider.

## Release

Releases are Developer ID signed, notarised, and published on GitHub Releases only, as a DMG, a zip, and a Sparkle appcast. `scripts/bump-version.sh <x.y.z>` sets the version in `project.yml` and dates the CHANGELOG section. Pushing a `v*` tag builds, notarises, and publishes the release in CI, and updates `Casks/notchemon.rb`. XcodeGen generates `Notchemon/Info.plist` and the entitlements file from `project.yml`, so neither is tracked.

[docs/releasing.md](docs/releasing.md) covers the one-time setup (the Sparkle key, the GitHub secrets, and making the repository public) and each release step.

## Credits

- **Sprites.** Creature sprites come from [SpriteCollab](https://github.com/PMDCollab/SpriteCollab), a community project in which many artists draw sprites in the style of the Mystery Dungeon games. The sprites are licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). The expanded notch names the artists of the sprite on screen, as the licence requires. The app downloads sprites at runtime and never bundles them.
- **Species data and fallback art.** Names, evolution data, portraits, and fallback sprites come from [PokéAPI](https://pokeapi.co), also fetched at runtime.

## License

The code is MIT licensed; see [LICENSE](LICENSE). The licence covers this code only. It grants no rights to any third-party trademark or artwork that the app displays at runtime.
