# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- The running app now notices an Accessibility grant. Each trust check also tries a real read of the Dock, and a read that succeeds counts as granted even while `AXIsProcessTrusted` still says no, which it can do inside a process that was running when the grant was made. The 0.2.2 checks asked only `AXIsProcessTrusted`, so the grant went unnoticed until a relaunch.
- The app logs trust checks, trust changes, and Dock reads under the `com.rohithgilla.Notchemon` subsystem, category `dock`, so `log show` answers what it saw.
- Debug builds use the bundle ID `com.rohithgilla.Notchemon.debug`, the display name "Notchemon Debug", their own defaults domain, and `~/Library/Application Support/Notchemon Debug/`. A grant or a saved state from a development build no longer attaches to the installed app.

## [0.2.2] - 2026-10-08

### Added

- Ways to remove files from the stash. Hover an icon and click its × badge, or right-click it and choose Remove from Stash. The context menu also has Open, Reveal in Finder, and Copy Path. Removing drops only the stash entry; the file stays where it is.
- Clear Stash, next to the stash count in the panel and in the menu-bar menu. After a clear, the panel shows "Stash cleared · Undo" for 5 seconds, and the menu-bar menu shows Undo Clear Stash. Undo puts the files back in their old order and keeps any file stashed since.
- Each stash icon shows its file name as a tooltip.

### Fixed

- Dock walking now starts once Accessibility is granted while the app runs. The app checked for the grant only when it became active or when macOS announced it, which a menu-bar app rarely sees, so the grant went unnoticed until a relaunch. While Dock walking is wanted and the permission is missing, the app now checks every 30 seconds, and every 2 seconds for two minutes after you choose Allow Dock Walking….
- The Motion submenu shows a Dock walking status line, such as "needs Accessibility", "on", "Dock is on the side", or "off in full screen", so a grant that did not take is visible.
- When the permission is missing, the Motion submenu offers "Accessibility shows it on but it still won't walk?", which explains that a grant to an older or development build does not carry over and opens the Accessibility settings.

## [0.2.1] - 2026-10-08

### Added

- **Click to Open** in the menu-bar menu. When it is on, the notch opens on a click instead of on hover, and stays open until you click empty panel space or the notch again.
- Focus sounds. A completed focus session can play Chime, Fanfare, or Ping. The default is Off.
- System stats in the expanded notch: CPU, memory, free disk space, and battery. The battery row is hidden on Macs without one. Stats are sampled only while the panel is open.

### Changed

- The asset check now also fails on franchise and species names in sources and in the built app, with a small explicit allowlist for PokéAPI attribution and the IP disclaimer.

## [0.2.0] - 2026-10-08

### Added

- Wandering. While the notch is closed, the creature walks along the strip below the menu bar, across the whole top edge by default. The Wander picker in the Motion submenu narrows it to near the notch or turns it off.
- Dock walking. The creature also walks along the top of a visible bottom Dock and hops between it and the top edge. Top Edge and Dock is the new default Wander setting, and On the Dock keeps it there. If an earlier build saved a Wander choice, that choice stays; the default applies only where none is saved, as on a new install. It needs Accessibility permission, which the app requests only from the Allow Dock Walking… menu item.
- Auto-hiding Dock. When the Dock hides automatically, the creature walks along the bottom edge of the screen. It rises onto the Dock while the Dock is shown and it is above the Dock, and drops back when the Dock hides.
- Animated SpriteCollab sprites, fetched at runtime and cached, with idle, sleep, hop, wake, and pose animations in eight facings. The creature turns to face the cursor.
- Fallback to PokéAPI's Showdown, Gen 5, and still sprites for species or animations that SpriteCollab lacks.
- Large portraits in the starter picker and an evolution reveal.
- Sprite artist credit line in the expanded notch, and a Credits section in the README.
- `NotchemonDebugSleepSeconds` debug default for a short sleep threshold.
- Automatic updates with Sparkle 2, signed with EdDSA, and a **Check for Updates…** menu item.
- **Launch at Login** menu toggle, off by default.
- About window with the version, licence, disclaimer, and credits.
- Signed and notarised DMG beside the zip, a release job that publishes both with a Sparkle appcast on `v*` tags, `scripts/bump-version.sh`, and [docs/releasing.md](docs/releasing.md).
- Floating notes, toggled with ⌃⌥⌘N or the **Floating Notes** menu item. Each note is a Markdown file in `~/Documents/Notchemon/Notes/`, with live styling, clickable tasks, a ⌘P quick switcher, auto-save, and conflict copies when another editor changes a note you are editing. The quick-note field can open it. `NotchemonNotesFolder` points it at another folder.
- When a note cannot be saved at quit, the app stays open and asks: **Try Again**, **Save a Copy…**, or **Quit Anyway**. It asks at logout and shutdown too.

### Changed

- Sprites scale by the creature's visible size to about 40 pt in the collapsed notch, in whole screen pixels, and stand on the bottom of the peek, which grows from 40 pt to 44 pt.

## [0.1.0] - 2026-10-07

### Added

- Notch overlay that sits on the built-in display, or draws a virtual notch on the main display. It follows screen and Space changes and uses a smaller peek over full-screen apps.
- Hover-to-expand panel with a spring animation, a 0.5 s collapse delay, and the ⌃⌥N hotkey. Menu-bar icons beside the closed notch stay clickable.
- `CreatureProvider` seam with a runtime PokéAPI provider, a cache-first disk cache, and an offline-capable second launch.
- `OriginalCreatureProvider` with procedural Core Graphics creatures, selected with `NotchemonCreatureProvider=original`.
- First-launch starter picker inside the expanded notch.
- `CreatureEngine` actor with idle, watching, sleeping, holding, and celebrating behaviours, all rendered as Core Animation animations.
- Focus timer with a ring around the notch, XP and levelling, level-up banner, and chained evolutions with a flash.
- `NotchemonDebugSessionSeconds` debug default for short sessions.
- Quick note that appends to `~/Documents/Notchemon/notes.md`.
- Five-slot file stash with security-scoped bookmarks, drop-in, drag-out, and a shake when full.
- Menu bar menu, `scripts/check-no-assets.sh`, `scripts/release.sh`, CI, and a Homebrew cask template.
