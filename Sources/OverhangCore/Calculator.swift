import Foundation

/// A small recursive-descent expression evaluator.
///
/// Supports `+ - * / % ^`, parentheses, unary minus, implicit multiplication
/// before parentheses/functions/constants (`2pi`, `3(4+1)`), the constants
/// `pi` and `e`, and the functions `sqrt abs sin cos tan asin acos atan ln log exp round floor ceil`.
/// Trig functions take radians.
public enum Calculator {
    public enum Error: Swift.Error, Equatable {
        case unexpectedCharacter(Character)
        case unexpectedEnd
        case unknownIdentifier(String)
        case trailingInput
        case notFinite
    }

    public static func evaluate(_ input: String) throws -> Double {
        var parser = Parser(tokens: try tokenize(input))
        let value = try parser.parseExpression()
        guard parser.isAtEnd else { throw Error.trailingInput }
        guard value.isFinite else { throw Error.notFinite }
        return value
    }

    /// Formats a result without float noise (e.g. `0.1 + 0.2` → `0.3`).
    public static func format(_ value: Double, maxFractionDigits: Int = 10) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if abs(value) >= 1e15 || (abs(value) < 1e-6 && value != 0) {
            formatter.numberStyle = .scientific
            formatter.maximumFractionDigits = 6
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - Tokens

    enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case op(Character)
        case lparen
        case rparen
    }

    static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "π", with: "pi"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if c.isNumber || c == "." {
                var j = i
                var text = ""
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "_" {
                    if chars[j] != "_" { text.append(chars[j]) }
                    j += 1
                }
                // Scientific notation: 1e5, 2.5E-3
                if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                    var k = j + 1
                    if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                    if k < chars.count, chars[k].isNumber {
                        text.append("e")
                        if chars[j + 1] == "-" { text.append("-") }
                        while k < chars.count, chars[k].isNumber {
                            text.append(chars[k])
                            k += 1
                        }
                        j = k
                    }
                }
                guard let value = Double(text) else { throw Error.unexpectedCharacter(c) }
                tokens.append(.number(value))
                i = j
            } else if c.isLetter {
                var j = i
                var name = ""
                while j < chars.count, chars[j].isLetter || chars[j].isNumber {
                    name.append(chars[j])
                    j += 1
                }
                tokens.append(.identifier(name.lowercased()))
                i = j
            } else if "+-*/%^".contains(c) {
                tokens.append(.op(c))
                i += 1
            } else if c == "(" {
                tokens.append(.lparen)
                i += 1
            } else if c == ")" {
                tokens.append(.rparen)
                i += 1
            } else {
                throw Error.unexpectedCharacter(c)
            }
        }
        return tokens
    }

    // MARK: - Parser
    //
    // expression := term (('+' | '-') term)*
    // term       := unary (('*' | '/' | '%') unary | implicit-multiplication)*
    // unary      := '-' unary | '+' unary | power
    // power      := primary ('^' unary)?          (right associative)
    // primary    := number | constant | function primary | '(' expression ')'

    struct Parser {
        let tokens: [Token]
        var index = 0

        init(tokens: [Token]) { self.tokens = tokens }

        var isAtEnd: Bool { index >= tokens.count }
        var current: Token? { isAtEnd ? nil : tokens[index] }

        mutating func advance() { index += 1 }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while let token = current, case let .op(op) = token, op == "+" || op == "-" {
                advance()
                let rhs = try parseTerm()
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            while let token = current {
                switch token {
                case let .op(op) where op == "*" || op == "/" || op == "%":
                    advance()
                    let rhs = try parseUnary()
                    switch op {
                    case "*": value *= rhs
                    case "/": value /= rhs
                    default: value = value.truncatingRemainder(dividingBy: rhs)
                    }
                case .lparen, .identifier, .number:
                    // Implicit multiplication: 2pi, 3(1+2), 2sqrt(4)
                    let rhs = try parseUnary()
                    value *= rhs
                default:
                    return value
                }
            }
            return value
        }

        mutating func parseUnary() throws -> Double {
            if let token = current, case let .op(op) = token, op == "-" || op == "+" {
                advance()
                let value = try parseUnary()
                return op == "-" ? -value : value
            }
            return try parsePower()
        }

        mutating func parsePower() throws -> Double {
            let base = try parsePrimary()
            if let token = current, case .op("^") = token {
                advance()
                let exponent = try parseUnary()
                return pow(base, exponent)
            }
            return base
        }

        mutating func parsePrimary() throws -> Double {
            guard let token = current else { throw Error.unexpectedEnd }
            switch token {
            case let .number(value):
                advance()
                return value
            case .lparen:
                advance()
                let value = try parseExpression()
                guard let closing = current, closing == .rparen else { throw Error.unexpectedEnd }
                advance()
                return value
            case let .identifier(name):
                advance()
                switch name {
                case "pi": return Double.pi
                case "e": return M_E
                case "tau": return 2 * Double.pi
                default: break
                }
                guard let function = Parser.functions[name] else { throw Error.unknownIdentifier(name) }
                let argument = try parsePrimary()
                return function(argument)
            case .rparen:
                throw Error.unexpectedCharacter(")")
            case let .op(op):
                throw Error.unexpectedCharacter(op)
            }
        }

        static let functions: [String: (Double) -> Double] = [
            "sqrt": { $0.squareRoot() },
            "abs": { Swift.abs($0) },
            "sin": { sin($0) },
            "cos": { cos($0) },
            "tan": { tan($0) },
            "asin": { asin($0) },
            "acos": { acos($0) },
            "atan": { atan($0) },
            "ln": { log($0) },
            "log": { log10($0) },
            "exp": { exp($0) },
            "round": { $0.rounded() },
            "floor": { $0.rounded(.down) },
            "ceil": { $0.rounded(.up) },
        ]
    }
}
