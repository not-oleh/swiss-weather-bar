import Foundation

// Weather warnings for Switzerland, as issued by MeteoSwiss and published on
// MeteoAlarm (EUMETNET). Terms: https://www.meteoalarm.org/en/live/page/terms-and-conditions
// — terms equivalent to CC BY 4.0, plus requirements for redistributors:
//   • show the issuing service ("MeteoSwiss") and the time of issue,
//   • link to www.meteoalarm.org and publish their delay disclaimer,
//   • keep the unmodified text available next to any shortened form,
//   • stay within 10 minutes of MeteoAlarm (we check every 5 minutes and hide
//     warnings once the last successful check is older than that).
//
// The Atom feed lists one entry per warning and area, each linking to the full
// CAP message. Swiss entries carry no region code, only the area's name; the
// CAP message has the area's outline. Outlines are remembered per area name,
// so after the first check only warnings that cover the chosen place are
// downloaded. The location never leaves the Mac: matching is done locally.

let meteoAlarmFeed = URL(string: "https://feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-switzerland")!
let meteoAlarmSite = URL(string: "https://www.meteoalarm.org")!
let meteoAlarmDisclaimer = """
    Time delays between this website and the www.meteoalarm.org website are possible. \
    For the most up-to-date awareness information as published by the participating \
    National Meteorological and Hydrological Services, please refer to www.meteoalarm.org.
    """

/// One language version of a warning, with the texts exactly as published.
struct WarningText {
    let language: String
    let event: String
    let headline: String
    let description: String
    let instruction: String
    let senderName: String
    let web: URL?
}

struct WeatherWarning {
    let identifier: String
    let sent: Date              // time of issue
    let onset: Date
    let expires: Date
    let level: Int              // MeteoAlarm awareness level: 2 yellow, 3 orange, 4 red
    let colour: String          // "yellow", "orange", "red"
    let area: String
    let references: Set<String> // identifiers of the warnings this one replaces
    let texts: [WarningText]

    /// The text in the user's preferred language if available, else English.
    var text: WarningText {
        for pref in Locale.preferredLanguages {
            let code = pref.prefix(2).lowercased()
            if let t = texts.first(where: { $0.language.lowercased().hasPrefix(code) }) { return t }
        }
        return texts.first { $0.language.lowercased().hasPrefix("en") } ?? texts[0]
    }

    var symbol: String {
        switch colour {
        case "red": return "🔴"
        case "orange": return "🟠"
        default: return "🟡"
        }
    }
}

typealias Polygon = [(lat: Double, lon: Double)]

/// Ray casting; fine for the small polygons of warning regions.
func contains(_ poly: Polygon, lat: Double, lon: Double) -> Bool {
    var inside = false
    var j = poly.count - 1
    for i in poly.indices {
        let a = poly[i], b = poly[j]
        if (a.lat > lat) != (b.lat > lat),
           lon < (b.lon - a.lon) * (lat - a.lat) / (b.lat - a.lat) + a.lon {
            inside.toggle()
        }
        j = i
    }
    return inside
}

@MainActor
final class WarningsClient {
    private let session: URLSession
    /// When the feed was last read successfully. Warnings are only shown while
    /// this is less than `maxAge` ago (MeteoAlarm allows at most 10 minutes' delay).
    private(set) var checkedAt: Date?
    static let maxAge: TimeInterval = 600
    private(set) var failed = false
    private var updating = false
    /// Warnings covering the place `matchedPlace` (a postcode id), newest check.
    private(set) var current: [WeatherWarning] = []
    private(set) var matchedPlace: Int?

    private let feed: URL
    private var outlines: [String: [Polygon]] = [:]         // area name → outline(s)
    private var messages: [URL: (WeatherWarning, [Polygon])] = [:]   // CAP messages never change
    private var ignored = Set<URL>()                        // messages that are not warnings
    /// Number of HTTP requests made so far (for keeping an eye on load).
    private(set) var requests = 0

    init(feed: URL = meteoAlarmFeed) {
        self.feed = feed
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": "SwissWeatherBar/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") (macOS menu bar app)"]
        session = URLSession(configuration: c)
    }

    var isFresh: Bool { checkedAt.map { Date().timeIntervalSince($0) < Self.maxAge } ?? false }

    /// Warnings for `place` that may be shown now: fresh, not yet expired, and
    /// not replaced by a newer warning. Most severe first, then by start time.
    func warnings(for place: Int) -> [WeatherWarning] {
        guard isFresh, matchedPlace == place else { return [] }
        let now = Date()
        return current.filter { $0.expires > now }
            .sorted { ($0.level, $1.onset) > ($1.level, $0.onset) }
    }

    /// Reads the feed and works out which warnings cover the given point.
    func update(place: Int, lat: Double, lon: Double) async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        do {
            requests += 1
            let (data, resp) = try await session.data(from: feed)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let now = Date()
            var found: [WeatherWarning] = []
            var live = Set<URL>()
            for e in parseXML(data)?.all("entry") ?? [] {
                guard e.value("status") == "Actual", e.value("message_type") != "Cancel",
                      let exp = e.value("expires").flatMap(parseDate), exp > now,
                      let href = e.all("link").first(where: { $0.attrs["type"] == "application/cap+xml" })?.attrs["href"],
                      let url = URL(string: href) else { continue }
                live.insert(url)
                guard !ignored.contains(url) else { continue }
                let area = e.value("areaDesc") ?? ""
                // A known area that does not cover the place needs no download.
                if messages[url] == nil, let known = outlines[area],
                   !known.contains(where: { contains($0, lat: lat, lon: lon) }) { continue }
                if messages[url] == nil {
                    requests += 1
                    let (cap, r) = try await session.data(from: url)
                    guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    guard let parsed = parseCAP(cap) else { ignored.insert(url); continue }
                    messages[url] = (parsed.warning, parsed.areas.flatMap(\.outline))
                    for a in parsed.areas where !a.outline.isEmpty { outlines[a.name] = a.outline }
                }
                if let (w, polys) = messages[url], polys.contains(where: { contains($0, lat: lat, lon: lon) }),
                   !found.contains(where: { $0.identifier == w.identifier }) {
                    found.append(w)
                }
            }
            messages = messages.filter { live.contains($0.key) }
            ignored.formIntersection(live)
            let replaced = found.reduce(into: Set<String>()) { $0.formUnion($1.references) }
            current = found.filter { !replaced.contains($0.identifier) }
            matchedPlace = place
            checkedAt = Date()
            failed = false
        } catch {
            NSLog("\(appName): warnings update failed: \(error)")
            failed = true
        }
    }

    // MARK: Parsing

    private func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    /// A CAP 1.2 message: the warning and the outline(s) of each of its areas.
    private func parseCAP(_ data: Data) -> (warning: WeatherWarning, areas: [(name: String, outline: [Polygon])])? {
        guard let alert = parseXML(data), alert.name == "alert",
              let id = alert.value("identifier"), let sent = alert.value("sent").flatMap(parseDate) else { return nil }
        let infos = alert.all("info")
        guard let first = infos.first,
              let expires = first.value("expires").flatMap(parseDate) else { return nil }
        let onset = (first.value("onset") ?? first.value("effective")).flatMap(parseDate) ?? sent
        // "3; orange; Severe"
        let awareness = first.all("parameter").first { $0.value("valueName") == "awareness_level" }?.value("value") ?? ""
        let parts = awareness.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let level = parts.first.flatMap { Int($0) } ?? 2
        guard level >= 2 else { return nil }         // level 1 (green) means no warning
        let colour = parts.count > 1 ? parts[1] : (level >= 4 ? "red" : level == 3 ? "orange" : "yellow")
        let areas = first.all("area")
        let outlines = areas.map { a -> (name: String, outline: [Polygon]) in
            let polys: [Polygon] = a.all("polygon").map { p in
                p.text.split(whereSeparator: \.isWhitespace).compactMap { pair -> (lat: Double, lon: Double)? in
                    let c = pair.split(separator: ",")
                    guard c.count == 2, let la = Double(c[0]), let lo = Double(c[1]) else { return nil }
                    return (la, lo)
                }
            }
            return (a.value("areaDesc") ?? "", polys.filter { $0.count >= 3 })
        }
        // "sender,identifier,sent sender,identifier,sent"
        let refs = Set((alert.value("references") ?? "").split(whereSeparator: \.isWhitespace)
            .compactMap { r -> String? in let f = r.split(separator: ","); return f.count >= 2 ? String(f[1]) : nil })
        let texts = infos.map { i in
            WarningText(language: i.value("language") ?? "en", event: i.value("event") ?? "",
                        headline: i.value("headline") ?? i.value("event") ?? "",
                        description: i.value("description") ?? "", instruction: i.value("instruction") ?? "",
                        senderName: i.value("senderName") ?? "MeteoSwiss",
                        web: i.value("web").flatMap { URL(string: $0) })
        }
        let w = WeatherWarning(identifier: id, sent: sent, onset: onset, expires: expires, level: level,
                               colour: colour, area: areas.first?.value("areaDesc") ?? "",
                               references: refs, texts: texts)
        return (w, outlines)
    }
}

// MARK: - Minimal XML tree (namespaces stripped)

final class XNode {
    let name: String
    let attrs: [String: String]
    var text = ""
    var children: [XNode] = []
    init(name: String, attrs: [String: String]) { self.name = name; self.attrs = attrs }

    func all(_ name: String) -> [XNode] { children.filter { $0.name == name } }
    /// Trimmed text of the first child with this name.
    func value(_ name: String) -> String? {
        children.first { $0.name == name }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    var stack: [XNode] = []
    var root: XNode?
    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let e = XNode(name: name, attrs: attributes)
        stack.last?.children.append(e)
        if root == nil { root = e }
        stack.append(e)
    }
    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        stack.removeLast()
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { stack.last?.text += s }
    func parser(_ p: XMLParser, foundCDATA d: Data) { stack.last?.text += String(decoding: d, as: UTF8.self) }
}

func parseXML(_ data: Data) -> XNode? {
    let p = XMLParser(data: data)
    p.shouldProcessNamespaces = true
    let b = TreeBuilder()
    p.delegate = b
    return p.parse() ? b.root : nil
}
