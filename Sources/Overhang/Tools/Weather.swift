import Foundation
import OverhangCore
import SwiftUI

/// Weather from Open-Meteo (free, no API key). The city is geocoded once and cached.
final class WeatherModel: ObservableObject {
    static let shared = WeatherModel()

    struct Day: Identifiable {
        let id: String
        let date: Date
        let code: Int
        let high: Double
        let low: Double
    }

    @Published private(set) var place = ""
    @Published private(set) var temperature: Double?
    @Published private(set) var feelsLike: Double?
    @Published private(set) var humidity: Double?
    @Published private(set) var wind: Double?
    @Published private(set) var code = 0
    @Published private(set) var isDay = true
    @Published private(set) var days: [Day] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false

    private var lastFetch: Date?
    private var lastKey = ""

    func refresh(force: Bool = false) {
        let city = UserDefaults.standard.string(forKey: Prefs.weatherCity) ?? ""
        let fahrenheit = UserDefaults.standard.bool(forKey: Prefs.weatherFahrenheit)
        let key = "\(city)|\(fahrenheit)"
        if !force, key == lastKey, let lastFetch, Date().timeIntervalSince(lastFetch) < 600 { return }
        guard !city.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Set a city in the field above."
            return
        }
        loading = true
        error = nil
        geocode(city) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(err):
                self.loading = false
                self.error = err.localizedDescription
            case let .success(location):
                self.place = location.label
                self.fetchForecast(location, fahrenheit: fahrenheit) {
                    self.lastFetch = Date()
                    self.lastKey = key
                }
            }
        }
    }

    // MARK: Networking

    private struct Location {
        let latitude: Double
        let longitude: Double
        let label: String
    }

    private struct GeoResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }

        let results: [Result]?
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let apparent: Double?
            let humidity: Double?
            let code: Int
            let wind: Double?
            let isDay: Int?

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case apparent = "apparent_temperature"
                case humidity = "relative_humidity_2m"
                case code = "weather_code"
                case wind = "wind_speed_10m"
                case isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            let time: [String]
            let code: [Int]
            let high: [Double]
            let low: [Double]

            enum CodingKeys: String, CodingKey {
                case time
                case code = "weather_code"
                case high = "temperature_2m_max"
                case low = "temperature_2m_min"
            }
        }

        let current: Current
        let daily: Daily
    }

    private func geocode(_ city: String, completion: @escaping (Result<Location, Error>) -> Void) {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        HTTP.getJSON(GeoResponse.self, url: components.url!) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(response):
                guard let first = response.results?.first else {
                    return completion(.failure(HTTP.Failure.message("Couldn't find “\(city)”.")))
                }
                let label = [first.name, first.admin1 ?? first.country].compactMap { $0 }.joined(separator: ", ")
                completion(.success(Location(latitude: first.latitude, longitude: first.longitude, label: label)))
            }
        }
    }

    private func fetchForecast(_ location: Location, fahrenheit: Bool, done: @escaping () -> Void) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh"),
        ]
        HTTP.getJSON(ForecastResponse.self, url: components.url!) { [weak self] result in
            guard let self else { return }
            self.loading = false
            switch result {
            case let .failure(error):
                self.error = error.localizedDescription
            case let .success(response):
                self.temperature = response.current.temperature
                self.feelsLike = response.current.apparent
                self.humidity = response.current.humidity
                self.wind = response.current.wind
                self.code = response.current.code
                self.isDay = (response.current.isDay ?? 1) == 1
                let parser = DateFormatter()
                parser.dateFormat = "yyyy-MM-dd"
                let daily = response.daily
                let count = min(daily.time.count, daily.code.count, daily.high.count, daily.low.count)
                self.days = (0..<count).compactMap { i in
                    guard let date = parser.date(from: daily.time[i]) else { return nil }
                    return Day(id: daily.time[i], date: date, code: daily.code[i], high: daily.high[i], low: daily.low[i])
                }
                done()
            }
        }
    }
}

/// Tiny JSON-over-HTTPS helper; callbacks arrive on the main queue.
enum HTTP {
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case let .message(text): return text }
        }
    }

    static func getJSON<T: Decodable>(_ type: T.Type, url: URL, headers: [String: String] = [:],
                                      completion: @escaping (Result<T, Error>) -> Void)
    {
        var request = URLRequest(url: url, timeoutInterval: 15)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<T, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(Failure.message("Server returned \(http.statusCode)."))
            } else if let data {
                do { result = .success(try JSONDecoder().decode(T.self, from: data)) }
                catch { result = .failure(Failure.message("Unexpected response format.")) }
            } else {
                result = .failure(Failure.message("No data."))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

struct WeatherView: View {
    @ObservedObject private var model = WeatherModel.shared
    @AppStorage(Prefs.weatherCity) private var city = "Cupertino"
    @AppStorage(Prefs.weatherFahrenheit) private var fahrenheit = false
    @State private var editingCity = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                InputField(placeholder: "City", text: $editingCity, symbol: "location") {
                    city = editingCity
                    model.refresh(force: true)
                }
                .frame(width: 220)
                Picker("", selection: $fahrenheit) {
                    Text("°C").tag(false)
                    Text("°F").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
                .labelsHidden()
                Spacer()
                if model.loading { ProgressView().controlSize(.small) }
                IconButton(symbol: "arrow.clockwise", size: 24, help: "Refresh") { model.refresh(force: true) }
            }
            if let error = model.error, model.temperature == nil {
                EmptyState(symbol: "cloud.sun", title: "Weather unavailable", message: error)
            } else if let temperature = model.temperature {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.place).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: WeatherCode.symbol(model.code, isDay: model.isDay))
                                .symbolRenderingMode(.multicolor).font(.system(size: 40))
                            Text("\(Int(temperature.rounded()))°").font(.system(size: 48, weight: .semibold, design: .rounded))
                        }
                        Text(WeatherCode.describe(model.code)).font(.system(size: 13))
                        HStack(spacing: 12) {
                            if let feels = model.feelsLike { Label("Feels \(Int(feels.rounded()))°", systemImage: "thermometer.medium") }
                            if let humidity = model.humidity { Label("\(Int(humidity))%", systemImage: "humidity") }
                            if let wind = model.wind { Label("\(Int(wind.rounded())) \(fahrenheit ? "mph" : "km/h")", systemImage: "wind") }
                        }
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(model.days.prefix(6)) { day in
                            VStack(spacing: 6) {
                                Text(Calendar.current.isDateInToday(day.date) ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                                Image(systemName: WeatherCode.symbol(day.code)).symbolRenderingMode(.multicolor).font(.system(size: 18))
                                    .frame(height: 22)
                                Text("\(Int(day.high.rounded()))°").font(.system(size: 13, weight: .semibold))
                                Text("\(Int(day.low.rounded()))°").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                            .frame(width: 52)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            editingCity = city
            model.refresh()
        }
        .onChange(of: fahrenheit) { _, _ in model.refresh(force: true) }
    }
}
