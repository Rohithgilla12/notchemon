# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Wandering. While the notch is closed, the creature walks along the strip below the menu bar, across the whole top edge by default. The Wander picker in the Motion submenu narrows it to near the notch or turns it off.
- Dock walking. The creature also walks along the top of a visible bottom Dock and hops between it and the top edge. Top Edge and Dock is the new default Wander setting, and On the Dock keeps it there. It needs Accessibility permission, which the app requests only from the Allow Dock Walking… menu item.
- Auto-hiding Dock. When the Dock hides automatically, the creature walks along the bottom edge of the screen. It rises onto the Dock while the Dock is shown and it is above the Dock, and drops back when the Dock hides.
- Animated SpriteCollab sprites, fetched at runtime and cached, with idle, sleep, hop, wake, and pose animations in eight facings. The creature turns to face the cursor.
- Fallback to PokéAPI's Showdown, Gen 5, and still sprites for species or animations that SpriteCollab lacks.
- Large portraits in the starter picker and an evolution reveal.
- Sprite artist credit line in the expanded notch, and a Credits section in the README.
- `NotchemonDebugSleepSeconds` debug default for a short sleep threshold.

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
