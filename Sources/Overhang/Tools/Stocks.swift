import Foundation
import SwiftUI

/// Quotes from Yahoo Finance's public chart endpoint (no key; unofficial, so it may change).
final class StocksModel: ObservableObject {
    static let shared = StocksModel()

    struct Quote: Identifiable {
        let id: String
        let symbol: String
        let price: Double
        let previousClose: Double
        let currency: String
        let closes: [Double]

        var change: Double { price - previousClose }
        var changePercent: Double { previousClose == 0 ? 0 : change / previousClose }
    }

    @Published private(set) var quotes: [Quote] = []
    @Published private(set) var failed: [String] = []
    @Published private(set) var loading = false
    @Published private(set) var updated: Date?

    private var timer: Timer?

    var symbols: [String] {
        (UserDefaults.standard.string(forKey: Prefs.stockSymbols) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }

    func startAutoRefresh() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    private struct ChartResponse: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable {
            let meta: Meta
            let indicators: Indicators?
        }
        struct Meta: Decodable {
            let symbol: String
            let currency: String?
            let regularMarketPrice: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
        }
        struct Indicators: Decodable { let quote: [QuoteSeries]? }
        struct QuoteSeries: Decodable { let close: [Double?]? }

        let chart: Chart
    }

    func refresh() {
        let list = symbols
        guard !list.isEmpty else {
            quotes = []
            return
        }
        loading = true
        let group = DispatchGroup()
        var results: [String: Quote] = [:]
        var failures: [String] = []
        for symbol in list {
            guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-="))),
                  let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=5m")
            else { continue }
            group.enter()
            HTTP.getJSON(ChartResponse.self, url: url, headers: ["User-Agent": "Mozilla/5.0"]) { result in
                defer { group.leave() }
                guard case let .success(response) = result,
                      let first = response.chart.result?.first,
                      let price = first.meta.regularMarketPrice
                else {
                    failures.append(symbol)
                    return
                }
                let closes = (first.indicators?.quote?.first?.close ?? []).compactMap { $0 }
                results[symbol] = Quote(
                    id: symbol,
                    symbol: first.meta.symbol,
                    price: price,
                    previousClose: first.meta.chartPreviousClose ?? first.meta.previousClose ?? price,
                    currency: first.meta.currency ?? "",
                    closes: closes
                )
            }
        }
        // HTTP callbacks run on main, so the dictionaries are only touched there.
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.quotes = list.compactMap { results[$0] }
            self.failed = failures
            self.loading = false
            self.updated = Date()
        }
    }
}

struct StocksView: View {
    @ObservedObject private var model = StocksModel.shared
    @AppStorage(Prefs.stockSymbols) private var symbolText = ""
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if editing {
                    InputField(placeholder: "AAPL, MSFT, BTC-USD, ^GSPC", text: $draft, symbol: "list.bullet") { commit() }
                    PillButton(title: "Save", prominent: true) { commit() }
                } else {
                    if let updated = model.updated {
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    if !model.failed.isEmpty {
                        Text("Not found: \(model.failed.joined(separator: ", "))")
                            .font(.system(size: 11)).foregroundStyle(Theme.negative).lineLimit(1)
                    }
                    Spacer()
                    if model.loading { ProgressView().controlSize(.small) }
                    PillButton(title: "Edit list", symbol: "pencil") {
                        draft = symbolText
                        editing = true
                    }
                    IconButton(symbol: "arrow.clockwise", size: 24) { model.refresh() }
                }
            }
            if model.quotes.isEmpty, !model.loading {
                EmptyState(symbol: "chart.line.uptrend.xyaxis", title: "No quotes",
                           message: "Add ticker symbols with “Edit list”. Quotes come from Yahoo Finance and may be delayed.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(model.quotes) { quote in
                            QuoteTile(quote: quote)
                        }
                    }
                }
            }
        }
        .onAppear { model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
    }

    private func commit() {
        symbolText = draft
        editing = false
        model.refresh()
    }
}

private struct QuoteTile: View {
    let quote: StocksModel.Quote

    var body: some View {
        let up = quote.change >= 0
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.symbol).font(.system(size: 13, weight: .bold))
                Text(quote.price.formatted(.number.precision(.fractionLength(2))) + " " + quote.currency)
                    .font(.system(size: 12).monospacedDigit())
            }
            .frame(width: 110, alignment: .leading)
            Sparkline(values: quote.closes, color: up ? Theme.positive : Theme.negative)
                .frame(height: 30)
            Text((up ? "+" : "") + (quote.changePercent * 100).formatted(.number.precision(.fractionLength(2))) + "%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(up ? Theme.positive : Theme.negative))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }
}
