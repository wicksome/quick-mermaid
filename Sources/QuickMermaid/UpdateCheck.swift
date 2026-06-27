import Foundation

/// Checks GitHub Releases for a newer version. Works without auth only when the
/// repo is public; on any failure (private repo → 404, offline, etc.) it stays
/// silent (reports "no newer version"), so it never nags or errors.
enum UpdateCheck {
    static let releasesURL = "https://github.com/wicksome/quick-mermaid/releases"
    private static let apiURL = "https://api.github.com/repos/wicksome/quick-mermaid/releases/latest"

    /// Reports the latest version string (e.g. "1.2.0") if it is newer than `current`,
    /// otherwise nil. The completion runs on the main queue.
    static func checkNewer(than current: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: apiURL) else { onMain(completion, nil); return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { onMain(completion, nil); return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            onMain(completion, isNewer(latest, than: current) ? latest : nil)
        }.resume()
    }

    /// Numeric semver comparison ("1.2.0" vs "1.2.3").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = parts(a), pb = parts(b)
        for i in 0 ..< max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ s: String) -> [Int] {
        s.split(separator: ".").map { Int($0) ?? 0 }
    }
    private static func onMain(_ c: @escaping (String?) -> Void, _ v: String?) {
        DispatchQueue.main.async { c(v) }
    }
}
