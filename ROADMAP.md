# Roadmap

This list is for planning. Notchemon stays free, local-first, and non-commercial, so each idea must follow the guardrails in the README.

Status key:

- **Shipped**: on `main`.
- **In progress**: an open PR or active branch.
- **Planned**: next up.
- **Later**: good fit, not scheduled.
- **Out of scope**: conflicts with the guardrails or the app's purpose.

## Companion

| Feature | Status | Notes |
| --- | --- | --- |
| Creature in the notch, starter picker, levels, evolution | Shipped | Sprites come from SpriteCollab and PokéAPI at runtime and are never bundled. |
| Walks along the top edge, sleeps, and wakes | Shipped | |
| Motion settings: calm, lively, or sitting idle; hop on approach; fidgets | Shipped | |
| Walks on the Dock, including auto-hiding Docks | In progress | PR #1. |
| Rests on top of the floating notes window | Later | Treats the notes window as another perch. |
| Reacts to Now Playing (dances while music plays) | Later | Depends on Now Playing. |

## Notch workspace

| Feature | Status | Notes |
| --- | --- | --- |
| Opens on hover, plus a global hotkey | Shipped | Hover and ⌃⌥N. |
| Click-to-open mode as an alternative to hover | Planned | |
| Reorder or hide the panel's tools | Later | |
| Spring expand and collapse | Shipped | |
| Virtual notch on Macs without one | Shipped | Can be turned off. |
| Keyboard shortcut for each tool | Later | |

## Productivity

| Feature | Status | Notes |
| --- | --- | --- |
| Quick note in the panel | Shipped | Appends to `~/Documents/Notchemon/notes.md`. |
| Floating notes, Raycast style | In progress | A floating Markdown notes window with its own hotkey. |
| Focus timer with ring and XP | Shipped | |
| Focus sounds for the timer | Later | |
| File stash ("shelf") | Shipped | Holds up to 5 files. |
| AirDrop from the stash | Planned | Uses `NSSharingService`. |
| Clear old stash items after a set time | Later | |
| Clipboard history | Planned | Search text, links, images, and files. Skip password-manager and transient pasteboard types. Stays on device. |
| Calendar: month view and today's events | Later | Uses EventKit and needs permission. |
| Reminders: tick off tasks | Later | Uses EventKit. |
| Teleprompter under the camera | Later | |
| Camera mirror | Later | Uses the camera and needs permission. |
| Now Playing controls and artwork | Later | |

## Information and utilities

| Feature | Status | Notes |
| --- | --- | --- |
| Weather and seven-day forecast | Later | Needs a free, keyless source. |
| Unit converter | Later | |
| System monitor: CPU, memory, disk, network, battery | Later | |
| Emoji picker | Later | |
| Stocks | Out of scope | Needs a market data feed, and it is off-theme. |
| Local AI chat, rewrite, and summarise (Apple Foundation Models) | Later | On-device only, and only where Apple Intelligence is available. |
| Usage meters for AI tools | Out of scope | It reads other tools' stored credentials. |
| Sales and revenue dashboard | Out of scope | It is off-theme and handles third-party API keys. |

## Privacy and distribution

| Feature | Status | Notes |
| --- | --- | --- |
| No telemetry, no account, data stays on the Mac | Shipped | |
| Open source (MIT) | Shipped | |
| Auto-updates (Sparkle), Launch at Login, About window, DMG, tagged releases | In progress | PR #2. |
| Homebrew cask | In progress | Works once the repo and its releases are public. |
| Paid licence, lifetime purchase, or seat limits | Out of scope | Guardrail 3: non-commercial, always. |
