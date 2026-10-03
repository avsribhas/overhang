import Foundation

public enum UnitCategory: String, CaseIterable, Sendable {
    case length = "Length"
    case mass = "Mass"
    case temperature = "Temperature"
    case volume = "Volume"
    case area = "Area"
    case speed = "Speed"
    case time = "Time"
    case data = "Data"
}

public struct UnitDefinition: Hashable, Sendable {
    public let symbol: String
    public let name: String
    public let category: UnitCategory
    /// Multiply by this to get the category's base unit (not used for temperature).
    public let factor: Double
    let aliases: [String]

    init(_ symbol: String, _ name: String, _ category: UnitCategory, _ factor: Double, _ aliases: [String] = []) {
        self.symbol = symbol
        self.name = name
        self.category = category
        self.factor = factor
        self.aliases = aliases
    }
}

/// A parsed "12 km to mi" style query.
public struct ConversionQuery: Equatable, Sendable {
    public let value: Double
    public let from: String
    public let to: String
}

public enum UnitConverter {
    public static let units: [UnitDefinition] = [
        // Length (base: metre)
        .init("mm", "millimetre", .length, 0.001, ["millimeter", "millimeters", "millimetres"]),
        .init("cm", "centimetre", .length, 0.01, ["centimeter", "centimeters", "centimetres"]),
        .init("m", "metre", .length, 1, ["meter", "meters", "metres"]),
        .init("km", "kilometre", .length, 1000, ["kilometer", "kilometers", "kilometres", "kms"]),
        .init("in", "inch", .length, 0.0254, ["inches", "\""]),
        .init("ft", "foot", .length, 0.3048, ["feet", "'"]),
        .init("yd", "yard", .length, 0.9144, ["yards"]),
        .init("mi", "mile", .length, 1609.344, ["miles"]),
        .init("nmi", "nautical mile", .length, 1852, ["nautical miles"]),
        // Mass (base: kilogram)
        .init("mg", "milligram", .mass, 0.000001, ["milligrams"]),
        .init("g", "gram", .mass, 0.001, ["grams", "gr"]),
        .init("kg", "kilogram", .mass, 1, ["kilograms", "kilo", "kilos"]),
        .init("t", "tonne", .mass, 1000, ["tonnes", "ton", "tons", "metric ton"]),
        .init("oz", "ounce", .mass, 0.028349523125, ["ounces"]),
        .init("lb", "pound", .mass, 0.45359237, ["lbs", "pounds"]),
        .init("st", "stone", .mass, 6.35029318, ["stones"]),
        // Temperature (handled specially)
        .init("°C", "celsius", .temperature, 1, ["c", "degc", "℃"]),
        .init("°F", "fahrenheit", .temperature, 1, ["f", "degf", "℉"]),
        .init("K", "kelvin", .temperature, 1, ["k"]),
        // Volume (base: litre)
        .init("ml", "millilitre", .volume, 0.001, ["milliliter", "milliliters", "millilitres"]),
        .init("l", "litre", .volume, 1, ["liter", "liters", "litres"]),
        .init("tsp", "teaspoon", .volume, 0.00492892159375, ["teaspoons"]),
        .init("tbsp", "tablespoon", .volume, 0.01478676478125, ["tablespoons"]),
        .init("floz", "fluid ounce", .volume, 0.0295735295625, ["fl oz", "fluid ounces"]),
        .init("cup", "cup", .volume, 0.2365882365, ["cups"]),
        .init("pt", "pint", .volume, 0.473176473, ["pints"]),
        .init("qt", "quart", .volume, 0.946352946, ["quarts"]),
        .init("gal", "gallon", .volume, 3.785411784, ["gallons"]),
        // Area (base: square metre)
        .init("m²", "square metre", .area, 1, ["m2", "sqm", "square meter", "square meters"]),
        .init("km²", "square kilometre", .area, 1_000_000, ["km2", "sqkm"]),
        .init("ft²", "square foot", .area, 0.09290304, ["ft2", "sqft", "square feet"]),
        .init("ac", "acre", .area, 4046.8564224, ["acre", "acres"]),
        .init("ha", "hectare", .area, 10000, ["hectares"]),
        // Speed (base: metres per second)
        .init("m/s", "metres per second", .speed, 1, ["mps"]),
        .init("km/h", "kilometres per hour", .speed, 1 / 3.6, ["kmh", "kph"]),
        .init("mph", "miles per hour", .speed, 0.44704, ["mi/h"]),
        .init("kn", "knot", .speed, 0.514444, ["knots", "kt"]),
        // Time (base: second)
        .init("ms", "millisecond", .time, 0.001, ["milliseconds"]),
        .init("s", "second", .time, 1, ["sec", "secs", "seconds"]),
        .init("min", "minute", .time, 60, ["mins", "minutes"]),
        .init("h", "hour", .time, 3600, ["hr", "hrs", "hours"]),
        .init("d", "day", .time, 86400, ["days"]),
        .init("wk", "week", .time, 604_800, ["week", "weeks"]),
        .init("yr", "year", .time, 31_557_600, ["year", "years"]),
        // Data (base: byte)
        .init("B", "byte", .data, 1, ["bytes"]),
        .init("KB", "kilobyte", .data, 1000, ["kilobytes"]),
        .init("MB", "megabyte", .data, 1_000_000, ["megabytes"]),
        .init("GB", "gigabyte", .data, 1_000_000_000, ["gigabytes"]),
        .init("TB", "terabyte", .data, 1_000_000_000_000, ["terabytes"]),
        .init("KiB", "kibibyte", .data, 1024, []),
        .init("MiB", "mebibyte", .data, 1_048_576, []),
        .init("GiB", "gibibyte", .data, 1_073_741_824, []),
    ]

    public static func units(in category: UnitCategory) -> [UnitDefinition] {
        units.filter { $0.category == category }
    }

    /// Finds a unit by symbol, name or alias. Exact-case symbol matches win (so `MB` ≠ `mb` ambiguity resolves sensibly).
    public static func unit(named raw: String) -> UnitDefinition? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let exact = units.first(where: { $0.symbol == trimmed }) { return exact }
        let key = trimmed.lowercased()
            .replacingOccurrences(of: "degrees ", with: "")
            .replacingOccurrences(of: "degree ", with: "")
        let keyWithoutDegree = key.replacingOccurrences(of: "°", with: "")
        for unit in units {
            let candidates = [unit.symbol.lowercased(), unit.name.lowercased()] + unit.aliases.map { $0.lowercased() }
            if candidates.contains(key) || candidates.contains(keyWithoutDegree) { return unit }
        }
        // Plural fallback: "metres" → "metre"
        if key.hasSuffix("s") {
            let singular = String(key.dropLast())
            return units.first { $0.name.lowercased() == singular }
        }
        return nil
    }

    public static func convert(_ value: Double, from: UnitDefinition, to: UnitDefinition) -> Double? {
        guard from.category == to.category else { return nil }
        if from.category == .temperature {
            return fromKelvin(toKelvin(value, from.symbol), to.symbol)
        }
        return value * from.factor / to.factor
    }

    static func toKelvin(_ value: Double, _ symbol: String) -> Double {
        switch symbol {
        case "°C": value + 273.15
        case "°F": (value - 32) * 5 / 9 + 273.15
        default: value
        }
    }

    static func fromKelvin(_ value: Double, _ symbol: String) -> Double {
        switch symbol {
        case "°C": value - 273.15
        case "°F": (value - 273.15) * 9 / 5 + 32
        default: value
        }
    }

    /// Parses queries like `12 km to mi`, `100usd in eur`, `-40 c = f`, `3.5 cups as ml`.
    public static func parse(_ input: String) -> ConversionQuery? {
        let pattern = #"^\s*(-?[0-9][0-9,_]*(?:\.[0-9]+)?|-?\.[0-9]+)\s*(.+?)\s+(?:to|in|as|into|=|->|→)\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, options: [], range: range),
              let numberRange = Range(match.range(at: 1), in: input),
              let fromRange = Range(match.range(at: 2), in: input),
              let toRange = Range(match.range(at: 3), in: input)
        else { return nil }
        let numberText = input[numberRange].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "_", with: "")
        guard let value = Double(numberText) else { return nil }
        return ConversionQuery(value: value, from: String(input[fromRange]), to: String(input[toRange]))
    }

    /// Converts a unit query. Returns nil when units are unknown or incompatible
    /// (callers may then try currency conversion).
    public static func evaluate(_ query: ConversionQuery) -> (value: Double, from: UnitDefinition, to: UnitDefinition)? {
        guard let from = unit(named: query.from), let to = unit(named: query.to),
              let result = convert(query.value, from: from, to: to)
        else { return nil }
        return (result, from, to)
    }

    /// Converts between currencies given rates relative to a common base (base itself must be present with 1.0).
    public static func convertCurrency(_ value: Double, from: String, to: String, rates: [String: Double]) -> Double? {
        let f = from.uppercased().trimmingCharacters(in: .whitespaces)
        let t = to.uppercased().trimmingCharacters(in: .whitespaces)
        guard let fromRate = rates[f], let toRate = rates[t], fromRate > 0 else { return nil }
        return value / fromRate * toRate
    }

    /// Maps common currency symbols to ISO codes.
    public static func currencyCode(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespaces) {
        case "$": "USD"
        case "€": "EUR"
        case "£": "GBP"
        case "¥": "JPY"
        case "₹": "INR"
        default: raw.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }
}
