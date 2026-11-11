import Foundation

/// Recursive-descent evaluator for arithmetic expressions.
///
/// Grammar:
///   expression := term (('+' | '-') term)*
///   term       := unary (('*' | '/') unary | implicit-multiplication)*
///   unary      := ('+' | '-') unary | power
///   power      := postfix ('^' unary)?
///   postfix    := primary '%'?
///   primary    := number | '(' expression ')' | constant | variable | function '(' expression ')'
enum ExpressionEvaluator {
    enum EvaluationError: Error {
        case syntax
        case unknownIdentifier(String)
    }

    private static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() },
        "abs": { Swift.abs($0) },
        "sin": { Foundation.sin($0) },
        "cos": { Foundation.cos($0) },
        "tan": { Foundation.tan($0) },
        "asin": { Foundation.asin($0) },
        "acos": { Foundation.acos($0) },
        "atan": { Foundation.atan($0) },
        "ln": { Foundation.log($0) },
        "log": { Foundation.log10($0) },
        "log2": { Foundation.log2($0) },
        "exp": { Foundation.exp($0) },
        "round": { $0.rounded() },
        "floor": { $0.rounded(.down) },
        "ceil": { $0.rounded(.up) },
    ]

    private static let constants: [String: Double] = [
        "pi": .pi,
        "π": .pi,
        "e": M_E,
    ]

    private static let operatorCharacters = Set("+-*/^%()")

    /// Cheap pre-check so plain words and bare numbers don't produce calculator results.
    static func looksLikeExpression(_ input: String) -> Bool {
        let text = normalize(input)
        guard !text.isEmpty, Double(text) == nil else { return false }
        let hasOperator = text.contains { operatorCharacters.contains($0) }
        let hasDigitOrConstant = text.contains(where: \.isNumber) || constants.keys.contains { text.contains($0) }
        return hasOperator && hasDigitOrConstant
    }

    static func evaluate(_ input: String, variables: [String: Double] = [:]) throws -> Double {
        var parser = Parser(characters: Array(normalize(input)), variables: variables)
        let value = try parser.parseExpression()
        guard parser.isAtEnd else { throw EvaluationError.syntax }
        return value
    }

    /// Recognizes a function of `x` such as "sin(x)", "x^2 - 1", "y = 2x + 1" or "f(x) = e^x".
    /// Returns the right-hand side, normalized, or nil when the input isn't a plottable function.
    static func functionOfX(_ input: String) -> String? {
        var text = normalize(input)
        for prefix in ["y=", "f(x)="] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        guard !text.isEmpty,
              text.contains(where: { operatorCharacters.contains($0) }),
              identifiers(in: text).contains("x")
        else { return nil }

        let samples = [-1.5, 0.5, 2.5].compactMap { try? evaluate(text, variables: ["x": $0]) }
        guard samples.count == 3, samples.contains(where: \.isFinite) else { return nil }
        return text
    }

    private static func identifiers(in text: String) -> Set<String> {
        var result: Set<String> = []
        var current = ""
        for character in text {
            if character.isLetter || (!current.isEmpty && character.isNumber) {
                current.append(character)
            } else if !current.isEmpty {
                result.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { result.insert(current) }
        return result
    }

    private static func normalize(_ input: String) -> String {
        var text = input.lowercased()
        let replacements: [(String, String)] = [
            ("×", "*"), ("÷", "/"), ("（", "("), ("）", ")"), ("，", ""), (",", ""), ("**", "^"),
        ]
        for (target, replacement) in replacements {
            text = text.replacingOccurrences(of: target, with: replacement)
        }
        return text.filter { !$0.isWhitespace }
    }

    private struct Parser {
        let characters: [Character]
        let variables: [String: Double]
        var index = 0

        var isAtEnd: Bool { index >= characters.count }
        private var peek: Character? { isAtEnd ? nil : characters[index] }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while let op = peek, op == "+" || op == "-" {
                index += 1
                let rhs = try parseTerm()
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            while let next = peek {
                if next == "*" || next == "/" {
                    index += 1
                    let rhs = try parseUnary()
                    value = next == "*" ? value * rhs : value / rhs
                } else if next == "(" || next.isLetter {
                    value *= try parseUnary()
                } else {
                    break
                }
            }
            return value
        }

        private mutating func parseUnary() throws -> Double {
            if peek == "-" {
                index += 1
                return -(try parseUnary())
            }
            if peek == "+" {
                index += 1
                return try parseUnary()
            }
            return try parsePower()
        }

        private mutating func parsePower() throws -> Double {
            let base = try parsePostfix()
            if peek == "^" {
                index += 1
                return pow(base, try parseUnary())
            }
            return base
        }

        private mutating func parsePostfix() throws -> Double {
            let value = try parsePrimary()
            if peek == "%" {
                index += 1
                return value / 100
            }
            return value
        }

        private mutating func parsePrimary() throws -> Double {
            guard let next = peek else { throw EvaluationError.syntax }

            if next == "(" {
                index += 1
                let value = try parseExpression()
                guard peek == ")" else { throw EvaluationError.syntax }
                index += 1
                return value
            }
            if next.isNumber || next == "." {
                return try parseNumber()
            }
            if next.isLetter {
                return try parseIdentifier()
            }
            throw EvaluationError.syntax
        }

        private mutating func parseNumber() throws -> Double {
            let start = index
            while let next = peek, next.isNumber || next == "." {
                index += 1
            }
            guard let value = Double(String(characters[start..<index])) else { throw EvaluationError.syntax }
            return value
        }

        private mutating func parseIdentifier() throws -> Double {
            let start = index
            while let next = peek, next.isLetter || (index > start && next.isNumber) {
                index += 1
            }
            let name = String(characters[start..<index])

            if let function = ExpressionEvaluator.functions[name] {
                guard peek == "(" else { throw EvaluationError.syntax }
                return function(try parsePrimary())
            }
            if let constant = ExpressionEvaluator.constants[name] {
                return constant
            }
            if let variable = variables[name] {
                return variable
            }
            throw EvaluationError.unknownIdentifier(name)
        }
    }
}
