import Foundation
import OverhangCore
import SwiftUI

/// Exchange rates from Frankfurter (European Central Bank data, free, no key), cached for 12 hours.
final class CurrencyRates: ObservableObject {
    static let shared = CurrencyRates()

    @Published private(set) var rates: [String: Double] = [:]
    @Published private(set) var date = ""
    private var fetchedAt: Date?

    private struct Response: Decodable {
        let base: String
        let date: String
        let rates: [String: Double]
    }

    init() {
        if let cached = UserDefaults.standard.dictionary(forKey: "currencyRates") as? [String: Double] {
            rates = cached
            date = UserDefaults.standard.string(forKey: "currencyRatesDate") ?? ""
            fetchedAt = UserDefaults.standard.object(forKey: "currencyRatesFetchedAt") as? Date
        }
    }

    func refreshIfNeeded() {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < 12 * 3600, !rates.isEmpty { return }
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else { return }
        HTTP.getJSON(Response.self, url: url) { [weak self] result in
            guard let self, case let .success(response) = result else { return }
            var all = response.rates
            all[response.base] = 1
            self.rates = all
            self.date = response.date
            self.fetchedAt = Date()
            UserDefaults.standard.set(all, forKey: "currencyRates")
            UserDefaults.standard.set(response.date, forKey: "currencyRatesDate")
            UserDefaults.standard.set(Date(), forKey: "currencyRatesFetchedAt")
        }
    }
}

struct ConverterView: View {
    @ObservedObject private var currency = CurrencyRates.shared
    @State private var query = ""
    @State private var toast: String?

    private let examples = ["12 km to mi", "100 usd to eur", "72 f to c", "3 cups to ml", "5 GB to MiB", "180 lb to kg", "60 mph to km/h", "2 acres to m²"]

    private var result: (text: String, detail: String)? {
        guard let parsed = UnitConverter.parse(query) else { return nil }
        if let converted = UnitConverter.evaluate(parsed) {
            return ("\(Calculator.format(converted.value, maxFractionDigits: 6)) \(converted.to.symbol)",
                    "\(Calculator.format(parsed.value)) \(converted.from.name) → \(converted.to.name)")
        }
        let from = UnitConverter.currencyCode(parsed.from)
        let to = UnitConverter.currencyCode(parsed.to)
        if let value = UnitConverter.convertCurrency(parsed.value, from: from, to: to, rates: currency.rates) {
            return (value.formatted(.number.precision(.fractionLength(2))) + " " + to,
                    "ECB reference rate" + (currency.date.isEmpty ? "" : " · \(currency.date)"))
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InputField(placeholder: "Try “12 km to mi” or “100 usd to inr”", text: $query, symbol: "arrow.left.arrow.right") {
                if let result { copy(result.text) }
            }
            Card(padding: 14) {
                if let result {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.text).font(.system(size: 28, weight: .semibold, design: .rounded)).textSelection(.enabled)
                            Text(result.detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        IconButton(symbol: "doc.on.doc", size: 28, help: "Copy") { copy(result.text) }
                    }
                } else {
                    Text(query.isEmpty ? "Type a conversion" : "Couldn't convert that. Units must be the same kind, or both currencies.")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        .frame(height: 50)
                }
            }
            Text("EXAMPLES").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    PillButton(title: example) { query = example }
                }
            }
            Spacer(minLength: 0)
        }
        .toast($toast)
        .onAppear { currency.refreshIfNeeded() }
    }

    private func copy(_ text: String) {
        Clipboard.copy(text)
        withAnimation { toast = "Copied \(text)" }
    }
}
