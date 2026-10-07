# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
