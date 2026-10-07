import Foundation

protocol DataFetcher: Sendable {
    func data(from url: URL) async throws -> Data
}

enum FetchError: Error, Equatable {
    case http(status: Int)
}

struct URLSessionFetcher: DataFetcher {
    var session: URLSession = Self.uncached

    /// `DiskCache` already keeps every response, so a URLCache would only
    /// hold a second copy.
    static let uncached: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.http(status: http.statusCode)
        }
        return data
    }
}
