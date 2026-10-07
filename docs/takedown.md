# Takedown plan

Use this plan if a rights holder asks for the creature content to be removed. One release moves every user to original creatures. Users keep their level and XP. No app code changes beyond the provider factory.

## Why one release is enough

- The app bundles no third-party creature assets. Sprites and names are downloaded at runtime and cached on each user's Mac, so there is nothing to scrub from past releases.
- All app logic uses the `CreatureProvider` protocol. `Notchemon/Creature/CreatureProviderFactory.swift` is the only file that names a concrete provider.
- `OriginalCreatureProvider` draws its own creatures with Core Graphics. It needs no network and has its own starters and evolution levels.
- When the saved species is unknown to the active provider, the app opens the starter picker. The new starter inherits the saved level and XP.

## Steps

1. Reply to the notice and confirm that you will comply. Do not argue the merits.
2. In `CreatureProviderFactory.swift`, make `OriginalCreatureProvider()` the default branch.
3. Delete `PokeAPICreatureProvider.swift` and `PokeAPIModels.swift`, and delete any README text that names the service. Delete the `DataFetcher` and `DiskCache` files only if nothing else uses them.
4. To remove downloaded content from users' Macs, delete `AppPaths.cache` once at launch, for example in `AppDelegate.applicationDidFinishLaunching`.
5. If the notice covers the name, rename the app. Update `project.yml`, the bundle display name, `README.md`, and `Casks/notchemon.rb`.
6. Add an entry to `CHANGELOG.md`, bump the version, tag it, and let CI publish the release. Update the cask's `sha256`.
7. Remove or edit old GitHub Releases if the notice requires it. Old binaries contain no creature assets; they download them at runtime.

## Rehearse it

Run the original provider locally at any time:

```sh
defaults write com.rohithgilla.Notchemon NotchemonCreatureProvider original
open .build/dd/Build/Products/Debug/Notchemon.app
defaults delete com.rohithgilla.Notchemon NotchemonCreatureProvider
```
