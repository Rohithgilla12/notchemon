import Foundation
import Testing
@testable import Notchemon

struct ForecastParsingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func parse(_ json: String) throws -> Forecast {
        try OpenMeteo.parse(Data(json.utf8), fetchedAt: now)
    }

    @Test func parsesTheCurrentReadingAndEachDay() throws {
        let forecast = try parse(#"""
        {"current": {"temperature_2m": 18.4, "weather_code": 3},
         "daily": {"time": ["2026-10-09", "2026-10-10"], "weather_code": [61, 0],
                   "temperature_2m_max": [19.2, 21.0], "temperature_2m_min": [11.0, 12.5]}}
        """#)
        let rainy = ForecastDay(date: "2026-10-09", condition: .rain, high: 19.2, low: 11.0)
        let clear = ForecastDay(date: "2026-10-10", condition: .clear, high: 21.0, low: 12.5)
        #expect(forecast == Forecast(temperature: 18.4, condition: .cloudy, days: [rainy, clear], fetchedAt: now))
    }

    @Test func keepsOnlyTheDaysEveryArrayCovers() throws {
        let forecast = try parse(#"""
        {"current": {"temperature_2m": 10, "weather_code": 0},
         "daily": {"time": ["2026-10-09", "2026-10-10", "2026-10-11", "2026-10-12"], "weather_code": [0, 1],
                   "temperature_2m_max": [15, 16, 17], "temperature_2m_min": [5, 6, 7, 8]}}
        """#)
        #expect(forecast.days.map(\.date) == ["2026-10-09", "2026-10-10"])
        #expect(forecast.days.map(\.low) == [5, 6])
    }

    @Test func aMissingDailyFieldLeavesNoDays() throws {
        let forecast = try parse(#"""
        {"current": {"temperature_2m": 10, "weather_code": 0},
         "daily": {"time": ["2026-10-09"], "temperature_2m_max": [15], "temperature_2m_min": [5]}}
        """#)
        #expect(forecast.days.isEmpty)
        #expect(forecast.temperature == 10)
    }

    @Test func aMissingDailyBlockLeavesNoDays() throws {
        let forecast = try parse(#"{"current": {"temperature_2m": 10, "weather_code": 0}}"#)
        #expect(forecast.days.isEmpty)
    }

    @Test func aMissingCurrentReadingThrows() {
        #expect(throws: DecodingError.self) {
            try parse(#"{"daily": {"time": [], "weather_code": [], "temperature_2m_max": [], "temperature_2m_min": []}}"#)
        }
    }

    @Test func unknownWeatherCodesReadAsUnknown() throws {
        let forecast = try parse(#"""
        {"current": {"temperature_2m": 10, "weather_code": 42},
         "daily": {"time": ["a", "b", "c"], "weather_code": [999, -1, 45],
                   "temperature_2m_max": [1, 2, 3], "temperature_2m_min": [0, 0, 0]}}
        """#)
        #expect(forecast.condition == .unknown)
        #expect(forecast.days.map(\.condition) == [.unknown, .unknown, .fog])
    }

    static let codes: [(Int, WeatherCondition)] = [
        (0, .clear), (3, .cloudy), (48, .fog), (55, .rain), (81, .rain), (73, .snow), (86, .snow), (96, .thunderstorm), (4, .unknown),
    ]

    @Test(arguments: codes)
    func mapsWeatherCodes(code: Int, condition: WeatherCondition) {
        #expect(WeatherCondition(code: code) == condition)
    }
}

struct OpenMeteoRequestTests {
    func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var query: [String: String] = [:]
        for item in items { query[item.name] = item.value }
        return query
    }

    @Test func roundsTheLocationToTwoDecimals() {
        let url = OpenMeteo.url(latitude: 51.507_351, longitude: -0.127_758)
        #expect(query(url)["latitude"] == "51.51")
        #expect(query(url)["longitude"] == "-0.13")
        #expect(!url.absoluteString.contains("51.507"))
        #expect(!url.absoluteString.contains("0.1277"))
    }

    @Test func asksForTheCurrentReadingAndTheDailyForecast() {
        let url = OpenMeteo.url(latitude: 1, longitude: 2)
        #expect(url.host() == "api.open-meteo.com")
        #expect(query(url)["current"] == "temperature_2m,weather_code")
        #expect(query(url)["daily"] == "weather_code,temperature_2m_max,temperature_2m_min")
    }
}

struct WeatherDisplayTests {
    let cached = Forecast(temperature: 12, condition: .clear, days: [], fetchedAt: Date())

    @Test func showsNothingWhileOff() {
        #expect(WeatherDisplay(enabled: false, access: .allowed, forecast: cached, failed: false) == .hidden)
    }

    @Test func deniedLocationShowsTheSettingsLineNotASpinner() {
        #expect(WeatherDisplay(enabled: true, access: .denied, forecast: nil, failed: false) == .locationOff)
        #expect(WeatherDisplay(enabled: true, access: .denied, forecast: cached, failed: false) == .locationOff)
    }

    @Test func showsACachedForecastAtOnceEvenAfterAFailedRefresh() {
        #expect(WeatherDisplay(enabled: true, access: .allowed, forecast: cached, failed: true) == .forecast(cached))
    }

    @Test func waitsForLocationOrTheFirstFetch() {
        #expect(WeatherDisplay(enabled: true, access: .undetermined, forecast: nil, failed: false) == .needsLocation)
        #expect(WeatherDisplay(enabled: true, access: .allowed, forecast: nil, failed: false) == .loading)
        #expect(WeatherDisplay(enabled: true, access: .allowed, forecast: nil, failed: true) == .unavailable)
    }

    @Test func aForecastStaysFreshForAnHour() {
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        let forecast = Forecast(temperature: 0, condition: .clear, days: [], fetchedAt: fetched)
        #expect(forecast.isFresh(at: fetched.addingTimeInterval(59 * 60)))
        #expect(!forecast.isFresh(at: fetched.addingTimeInterval(61 * 60)))
    }
}

@MainActor
struct WeatherServiceTests {
    @Test func startsOffWithNothingToShow() {
        let service = WeatherService(fetcher: StubFetcher())
        #expect(service.display == .hidden)
    }

    @Test func requestsTheRoundedLocationAndDropsAReplyThatLandsAfterWeatherIsOff() async {
        let reply = Data(#"{"current": {"temperature_2m": 10, "weather_code": 0}}"#.utf8)
        let fetcher = StubFetcher([OpenMeteo.url(latitude: 48.86, longitude: 2.35): reply])
        let service = WeatherService(fetcher: fetcher)
        await service.fetch(latitude: 48.856_613, longitude: 2.352_222)
        #expect(fetcher.requests.count == 1)
        #expect(fetcher.requests.first?.query?.contains("latitude=48.86&longitude=2.35") == true)
        #expect(service.forecast == nil)
        #expect(!service.failed)
    }
}

struct WeatherTextTests {
    let britain = Locale(identifier: "en_GB")

    @Test func summarisesTheCurrentReading() {
        let forecast = Forecast(temperature: 18.4, condition: .cloudy, days: [], fetchedAt: Date())
        #expect(WeatherText.summary(forecast) == "Weather · Cloudy 18°C")
    }

    @Test func namesEachDayByItsWeekday() {
        let day = ForecastDay(date: "2026-10-09", condition: .rain, high: 19.6, low: -0.4)
        #expect(WeatherText.day(day, locale: britain) == "Fri · Rain · 20° / 0°")
    }

    @Test func keepsADateItCannotRead() {
        #expect(WeatherText.weekday("soon", locale: britain) == "soon")
    }
}

struct WeatherPreferenceTests {
    @Test func weatherIsOffByDefaultAndInOlderFiles() throws {
        #expect(!Preferences().showsWeather)
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(#"{"focusMinutes": 45}"#.utf8))
        #expect(!decoded.showsWeather)
    }

    @Test func aBadValueReadsAsOffWithoutLosingTheOtherPreferences() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(#"{"showsWeather": "yes", "fidgets": false}"#.utf8))
        #expect(!decoded.showsWeather)
        #expect(!decoded.fidgets)
    }

    @Test func roundTrips() throws {
        var preferences = Preferences()
        preferences.showsWeather = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded.showsWeather)
    }
}
