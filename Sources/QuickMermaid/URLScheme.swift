import Foundation

/// The `quickmermaid://` custom URL scheme: clickable links that carry diagram
/// source text. A link renders the same way as any other input source — the
/// decoded text is handed to the renderer, which auto-detects Mermaid/PlantUML.
///
/// Format: `quickmermaid://render?data=<base64url>` where `<base64url>` is the
/// UTF-8 source text in URL-safe base64 (RFC 4648 §5: `+/` → `-_`, padding
/// stripped). base64url is used because a plain base64 payload's `+` and `/`
/// would be mangled in a URL.
enum URLScheme {
    static let scheme = "quickmermaid"
    static let host = "render"
    static let dataQueryItem = "data"

    /// Builds a `quickmermaid://render?data=…` URL for the given source text.
    /// Returns nil only if the text is not representable as UTF-8 (never, in practice).
    static func encode(text: String) -> URL? {
        guard let data = text.data(using: .utf8) else { return nil }
        let b64url = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: dataQueryItem, value: b64url)]
        return components.url
    }

    /// Decodes the source text from a `quickmermaid://render?data=…` URL.
    /// Returns nil for a wrong scheme, a missing/empty `data`, or invalid base64url.
    static func decode(url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == dataQueryItem })?.value,
              !value.isEmpty else { return nil }
        return decodeBase64URL(value)
    }

    /// Decodes a URL-safe base64 string (no padding) to its UTF-8 text.
    private static func decodeBase64URL(_ s: String) -> String? {
        var b64 = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore the `=` padding base64 decoding requires (length to a multiple of 4).
        let remainder = b64.count % 4
        if remainder > 0 {
            b64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: b64),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}
