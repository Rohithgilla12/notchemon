import Foundation

enum WeatherCondition: Sendable, Equatable {
    case clear, cloudy, fog, rain, snow, thunderstorm, unknown

    /// WMO weather interpretation codes, as Open-Meteo reports them.
    init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2, 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .thunderstorm
        default: self = .unknown
        }
    }

    var symbolName: String {
        switch self {
        case .clear: "sun.max"
        case .cloudy: "cloud"
        case .fog: "cloud.fog"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        case .thunderstorm: "cloud.bolt.rain"
        case .unknown: "questionmark"
        }
    }

    var label: String {
        switch self {
        case .clear: "Clear"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .rain: "Rain"
        case .snow: "Snow"
        case .thunderstorm: "Storms"
        case .unknown: "Unknown"
        }
    }
}

struct ForecastDay: Sendable, Equatable {
    /// The local calendar date, as `yyyy-MM-dd`.
    let date: String
    let condition: WeatherCondition
    let high: Double
    let low: Double
}

/// Temperatures are in degrees Celsius.
struct Forecast: Sendable, Equatable {
    static let lifetime: TimeInterval = 3600

    let temperature: Double
    let condition: WeatherCondition
    let days: [ForecastDay]
    let fetchedAt: Date

    func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) < Self.lifetime
    }
}

enum OpenMeteo {
    /// Two decimal places is about 1 km, all a forecast needs, so the
    /// request never carries the precise location.
    static func url(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: rounded(latitude)),
            URLQueryItem(name: "longitude", value: rounded(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components.url!
    }

    static func rounded(_ degrees: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), degrees)
    }

    /// The daily arrays are parallel, but nothing guarantees equal lengths,
    /// so a day exists only where all four have a value.
    static func parse(_ data: Data, fetchedAt: Date) throws -> Forecast {
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        let dates = reply.daily?.time ?? []
        let codes = reply.daily?.codes ?? []
        let highs = reply.daily?.highs ?? []
        let lows = reply.daily?.lows ?? []
        let count = min(dates.count, codes.count, highs.count, lows.count)
        let days = (0..<count).map { index in
            ForecastDay(date: dates[index], condition: WeatherCondition(code: codes[index]), high: highs[index], low: lows[index])
        }
        return Forecast(
            temperature: reply.current.temperature,
            condition: WeatherCondition(code: reply.current.code),
            days: days,
            fetchedAt: fetchedAt
        )
    }

    private struct Reply: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let code: Int

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case code = "weather_code"
            }
        }

        struct Daily: Decodable {
            let time: [String]?
            let codes: [Int]?
            let highs: [Double]?
            let lows: [Double]?

            enum CodingKeys: String, CodingKey {
                case time
                case codes = "weather_code"
                case highs = "temperature_2m_max"
                case lows = "temperature_2m_min"
            }
        }

        let current: Current
        let daily: Daily?
    }
}

enum LocationAccess: Sendable, Equatable {
    case undetermined, denied, allowed
}

/// What the menu shows for weather.
enum WeatherDisplay: Equatable {
    case hidden
    case needsLocation
    case locationOff
    case loading
    case unavailable
    case forecast(Forecast)

    init(enabled: Bool, access: LocationAccess, forecast: Forecast?, failed: Bool) {
        if !enabled {
            self = .hidden
        } else if access == .denied {
            self = .locationOff
        } else if let forecast {
            self = .forecast(forecast)
        } else if access == .undetermined {
            self = .needsLocation
        } else {
            self = failed ? .unavailable : .loading
        }
    }
}
