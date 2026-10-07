import Foundation

/// The only file that names a concrete provider. Flipping the user default
/// `NotchemonCreatureProvider` to `original` swaps every creature in the app;
/// see docs/takedown.md.
enum CreatureProviderFactory {
    static let defaultsKey = "NotchemonCreatureProvider"

    static func make(defaults: UserDefaults = .standard, cacheRoot: URL = AppPaths.cache) -> any CreatureProvider {
        switch defaults.string(forKey: defaultsKey) {
        case "original":
            OriginalCreatureProvider()
        default:
            PokeAPICreatureProvider(cache: DiskCache(root: cacheRoot), fetcher: URLSessionFetcher())
        }
    }
}
