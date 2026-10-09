import SwiftUI

/// Weather in the menu-bar menu: one line, with the coming days in its
/// submenu. The open panel's tools column has no room left for a card.
struct WeatherMenuItem: View {
    let weather: WeatherService

    var body: some View {
        switch weather.display {
        case .hidden:
            EmptyView()
        case .needsLocation:
            Button("Allow Location for Weather…") { weather.requestAccess() }
        case .locationOff:
            Button("Location off — Open Settings") { WeatherService.openLocationSettings() }
        case .loading:
            Text("Weather · Loading…")
        case .unavailable:
            Text("Weather · Unavailable")
        case .forecast(let forecast):
            Menu {
                ForEach(forecast.days.prefix(5), id: \.date) { day in
                    Text(WeatherText.day(day))
                }
            } label: {
                Label(WeatherText.summary(forecast), systemImage: forecast.condition.symbolName)
            }
        }
    }
}

enum WeatherText {
    static func summary(_ forecast: Forecast) -> String {
        "Weather · \(forecast.condition.label) \(degrees(forecast.temperature))C"
    }

    static func day(_ day: ForecastDay, locale: Locale = .current) -> String {
        "\(weekday(day.date, locale: locale)) · \(day.condition.label) · \(degrees(day.high)) / \(degrees(day.low))"
    }

    static func degrees(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°"
    }

    /// Open-Meteo's dates are already local to the forecast, so both sides
    /// use UTC to keep the day from shifting.
    static func weekday(_ date: String, locale: Locale) -> String {
        let utc = TimeZone(identifier: "UTC")!
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = utc
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed = parser.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = utc
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: parsed)
    }
}
