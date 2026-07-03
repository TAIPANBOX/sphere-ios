import Foundation

/// Converts a user-typed query into a safe FTS5 MATCH expression.
///
/// FTS5 treats `" * ( ) + - : ^` and the words AND OR NOT NEAR as syntax.
/// Raw user input (apostrophes, quotes, dashes) would break the MATCH query
/// and silently degrade recall to the recent-only fallback.
///
/// Strategy: keep only runs of Unicode letters/digits, wrap each token in
/// double quotes so it is matched as a literal phrase, then OR them together.
/// Returns an empty string when no usable tokens remain.
public func sanitizeFtsQuery(_ raw: String) -> String {
    raw.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        .map { "\"\($0)\"" }
        .joined(separator: " OR ")
}
