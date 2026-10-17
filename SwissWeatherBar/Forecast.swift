import Foundation

// Client for MeteoSwiss Open Government Data, local forecasts ("ogd-local-forecasting").
// Licence: CC BY 4.0 — attribution "Source: MeteoSwiss" is shown in the app.
// Docs: https://opendatadocs.meteoswiss.ch/e-forecast-data/e4-local-forecast-data
//
// Every hourly run publishes one CSV per parameter covering all ~5,800 forecast
// points (≈30 MB each). Instead of downloading whole files we binary-search the
// one row(s) we need with small HTTP Range requests. Rows are either grouped by
// point or by timestamp (it varies per file, so we detect it). Within a file (or
// a timestamp block) the postal-code points (point_type_id 2) form one
// contiguous run sorted by id; stations and mountain points can come before
// and/or after that run.

let ogdBase = "https://data.geo.admin.ch/ch.meteoschweiz.ogd-local-forecasting"

enum Param: String, CaseIterable {
    case temp = "tre200h0"          // °C, hourly mean
    case icon = "jww003i0"          // pictogram number, preceding 3 h
    case rainProb = "rp0003i0"      // %, preceding 3 h
    case wind = "fu3010h0"          // km/h, hourly mean
    case gust = "fu3010h1"          // km/h, hourly max
    case windDir = "dkl010h0"       // degrees
    case dayIcon = "jp2000d0"       // pictogram number, daytime
    case dayMin = "tre200pn"        // °C, local day
    case dayMax = "tre200px"
    case dayRain = "rka150p0"       // mm, local day
    case dayRainLo = "rreq10p0"     // mm, 10 % quantile
    case dayRainHi = "rreq90p0"     // mm, 90 % quantile
}

struct Day: Codable {
    let date: Date
    let icon: Int
    let tmin: Double
    let tmax: Double
    let precip: Double
    let precipMin: Double
    let precipMax: Double
}

struct Slot: Codable { // one 3-hour step of the local forecast
    let time: Date
    let icon: Int
    let temp: Double?
    let rainProb: Double?
}

struct Weather: Codable {
    let temp: Double
    let icon: Int
    let issued: Date
    let days: [Day]
    let slots: [Slot]
    let wind: Double?
    let gust: Double?
    let windDir: Int?
}

enum OGDError: Error { case noRun, missing(String) }

private struct Row {
    let id: Int, type: Int, ts: Int64, value: Double
    init?(_ line: Substring) {
        let f = line.split(separator: ";", omittingEmptySubsequences: false)
        guard f.count >= 4, let id = Int(f[0]), let type = Int(f[1]), let ts = Int64(f[2]) else { return nil }
        self.id = id; self.type = type; self.ts = ts; self.value = Double(f[3]) ?? .nan
    }
}

private final class RemoteCSV {
    let param: Param
    let url: URL
    let size: Int
    let head: Data                  // first KB: header line plus a few rows
    var dataStart = 0
    var pointMajor = true
    var firstTs: Int64 = 0          // timestamp of the first data row
    /// Byte offset of some postal-code row, per timestamp block (key 0 when grouped by
    /// point). A non-postal row before it lies before the postal run, one after it after.
    var anchors: [Int64: Int] = [:]
    init(param: Param, url: URL, size: Int, head: Data) {
        self.param = param; self.url = url; self.size = size; self.head = head
    }
}

final class OGDClient {
    private let session: URLSession
    private(set) var run: Date?
    private let lock = NSLock()
    private var _requests = 0
    /// Number of HTTP requests made so far (for logging / keeping an eye on load).
    var requests: Int { lock.lock(); defer { lock.unlock() }; return _requests }
    private func count() { lock.lock(); _requests += 1; lock.unlock() }
    /// Where a point's rows were found last time, as a fraction of the file size.
    /// Consecutive runs have the same layout, so this makes later searches short.
    /// In files grouped by timestamp the key is the block's position in the file
    /// (hours after its first row), not the timestamp itself: each run starts an
    /// hour later, so a given timestamp moves up by one block.
    private var hints: [String: Double] = [:]
    private func hintKey(_ f: RemoteCSV, _ point: Int, _ ts: Int64) -> String {
        "\(f.param.rawValue)/\(point)/" + (f.pointMajor ? "all" : "+\(hours(f.firstTs, ts))h")
    }
    private func hint(_ f: RemoteCSV, _ point: Int, _ ts: Int64) -> Int? {
        let key = hintKey(f, point, ts)
        lock.lock(); defer { lock.unlock() }
        return hints[key].map { Int($0 * Double(f.size)) }
    }
    private func remember(_ f: RemoteCSV, _ point: Int, _ ts: Int64, _ off: Int) {
        let key = hintKey(f, point, ts)
        lock.lock(); hints[key] = Double(off) / Double(f.size); lock.unlock()
    }
    private var files: [Param: RemoteCSV] = [:]

    private static let utc: TimeZone = TimeZone(identifier: "UTC")!
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.timeZone = utc; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmm"; return f
    }()

    init() {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 20
        c.httpMaximumConnectionsPerHost = 4
        c.httpAdditionalHeaders = ["User-Agent": "SwissWeatherBar/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") (macOS menu bar app)"]
        session = URLSession(configuration: c)
    }

    // MARK: Run discovery

    /// Finds the newest run whose files are all published. Returns true if it changed.
    func updateRun() async throws -> Bool {
        let now = Date()
        let hour = Calendar(identifier: .gregorian).dateInterval(of: .hour, for: now)!.start
        for back in 0..<8 {
            let cand = hour.addingTimeInterval(Double(-back) * 3600)
            if cand == run { return false }
            if let found = try await probeRun(cand) {
                files = found
                run = cand
                return true
            }
        }
        if run != nil { return false }
        throw OGDError.noRun
    }

    private func probeRun(_ run: Date) async throws -> [Param: RemoteCSV]? {
        let s = Self.stamp.string(from: run)
        let folder = String(s.prefix(8)) + "-ch"
        return try await withThrowingTaskGroup(of: (Param, RemoteCSV?).self) { g in
            for p in Param.allCases {
                let url = URL(string: "\(ogdBase)/\(folder)/vnut12.lssw.\(s).\(p.rawValue).csv")!
                g.addTask {
                    // A ranged GET tells us the total size (Content-Range) and gives us the
                    // header in one request. HEAD is unreliable: the CDN gzips smaller
                    // files and then omits Content-Length.
                    var req = URLRequest(url: url)
                    req.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
                    req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                    self.count()
                    let (data, resp) = try await self.session.data(for: req)
                    guard let h = resp as? HTTPURLResponse, h.statusCode == 206,
                          let cr = h.value(forHTTPHeaderField: "Content-Range"),
                          let total = cr.split(separator: "/").last.flatMap({ Int($0) }) else { return (p, nil) }
                    return (p, RemoteCSV(param: p, url: url, size: total, head: data))
                }
            }
            var out: [Param: RemoteCSV] = [:]
            for try await (p, f) in g {
                guard let f = f else { g.cancelAll(); return nil }
                out[p] = f
            }
            return out
        }
    }

    // MARK: Range reads

    private func bytes(_ f: RemoteCSV, _ lo: Int, _ len: Int) async throws -> Data {
        let hi = min(f.size, lo + len) - 1
        guard hi >= lo else { return Data() }
        var req = URLRequest(url: f.url)
        req.setValue("bytes=\(lo)-\(hi)", forHTTPHeaderField: "Range")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        count()
        let (data, resp) = try await session.data(for: req)
        guard let h = resp as? HTTPURLResponse, h.statusCode == 206 || h.statusCode == 200 else {
            throw OGDError.missing(f.url.lastPathComponent)
        }
        // A server ignoring Range would send everything; keep just the slice we asked for.
        return h.statusCode == 200 ? data.subdata(in: lo..<min(data.count, hi + 1)) : data
    }

    private func lines(_ d: Data, partialFirst: Bool) -> [Substring] {
        let s = String(decoding: d, as: UTF8.self)   // Latin-1 only matters for names, not values
        var l = s.split(separator: "\n", omittingEmptySubsequences: true)
        if partialFirst, !l.isEmpty { l.removeFirst() }
        if !s.hasSuffix("\n"), !l.isEmpty { l.removeLast() }
        return l
    }

    private func prepare(_ f: RemoteCSV) async throws {
        guard f.dataStart == 0 else { return }
        let head = f.head
        guard let nl = head.firstIndex(of: UInt8(ascii: "\n")) else { throw OGDError.missing("header") }
        f.dataStart = nl + 1
        let rows = lines(head, partialFirst: true).compactMap(Row.init)
        guard rows.count >= 2 else { throw OGDError.missing("rows") }
        f.pointMajor = rows[0].id == rows[1].id && rows[0].type == rows[1].type
        f.firstTs = rows[0].ts
    }

    /// First complete row starting after byte `off` (or at it, at the data start), with its offset.
    private func row(after off: Int, in f: RemoteCSV) async throws -> (Row, Int)? {
        let d = try await bytes(f, off, 128)
        var start = off
        if off != f.dataStart {
            guard let nl = d.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            start = off + (nl - d.startIndex) + 1
        }
        guard let r = lines(d, partialFirst: off != f.dataStart).first.flatMap(Row.init) else { return nil }
        return (r, start)
    }

    /// Is row `r` (starting at `at`) ordered before the target (point, ts)?
    private func less(_ r: Row, at: Int, _ point: Int, _ ts: Int64, _ f: RemoteCSV, unknownAfter: Bool) -> Bool {
        let block: Int64 = f.pointMajor ? 0 : r.ts
        if !f.pointMajor, r.ts != ts { return r.ts < ts }
        if r.type == 2 {
            f.anchors[block] = at
            return f.pointMajor ? (r.id, r.ts) < (point, ts) : r.id < point
        }
        if let a = f.anchors[block] { return at < a }
        return !unknownAfter
    }

    /// Byte window [lo, hi) such that the first row ≥ (point, ts) starts inside it.
    private func locate(_ point: Int, _ ts: Int64, in f: RemoteCSV, guess: Int? = nil, window w: Int = 24_000,
                        unknownAfter: Bool) async throws -> (Int, Int) {
        func isLess(_ x: (Row, Int)?) -> Bool? {
            x.map { less($0.0, at: $0.1, point, ts, f, unknownAfter: unknownAfter) }
        }
        var lo = f.dataStart, hi = f.size
        if let g = guess {
            let a = max(f.dataStart, g - w), b = min(f.size, g + w)
            let ra = try await row(after: a, in: f), rb = try await row(after: b, in: f)
            if a == f.dataStart || isLess(ra) == true, b == f.size || isLess(rb) == false {
                lo = a; hi = b
            }
        }
        while hi - lo > 4096 {
            let mid = (lo + hi) / 2
            if isLess(try await row(after: mid, in: f)) == true { lo = mid } else { hi = mid }
        }
        return (lo, hi)
    }

    /// All rows of one point (for files grouped by point).
    private func series(_ point: Int, in f: RemoteCSV) async throws -> [Int64: Double] {
        for unknownAfter in [false, true] {
            let (lo, hi) = try await locate(point, 0, in: f, guess: hint(f, point, 0), window: 6_000,
                                            unknownAfter: unknownAfter)
            remember(f, point, 0, lo)
            let d = try await bytes(f, lo, hi - lo + 16_384)
            var out: [Int64: Double] = [:]
            for l in lines(d, partialFirst: lo != f.dataStart) {
                guard let r = Row(l), r.type == 2 else { continue }
                if r.id == point { if !r.value.isNaN { out[r.ts] = r.value } } else if r.id > point { break }
            }
            if !out.isEmpty { return out }
        }
        return [:]
    }

    /// Values of one point at the given timestamps, whatever the file layout.
    func values(_ point: Int, _ p: Param, at stamps: [Int64]) async throws -> [Int64: Double] {
        guard let f = files[p] else { throw OGDError.missing(p.rawValue) }
        try await prepare(f)
        if f.pointMajor {
            return try await series(point, in: f).filter { stamps.contains($0.key) }
        }
        // Timestamp-major: one search per timestamp. Blocks are about equally
        // sized, so after the first hit we can guess where the next one is.
        var perHour: Double?
        if stamps.count > 1,
           let tail = lines(try await bytes(f, f.size - 128, 128), partialFirst: true).last.flatMap(Row.init) {
            perHour = Double(f.size - f.dataStart) / Double(max(1, hours(f.firstTs, tail.ts) + 1))
        }
        var out: [Int64: Double] = [:]
        var last: (ts: Int64, off: Int)?
        for ts in stamps.sorted() {
            let remembered = hint(f, point, ts)
            let guess = remembered ?? last.flatMap { l in perHour.map { l.off + Int(Double(hours(l.ts, ts)) * $0) } }
            for unknownAfter in [false, true] {
                let (lo, hi) = try await locate(point, ts, in: f, guess: guess, window: remembered == nil ? 24_000 : 6_000,
                                                unknownAfter: unknownAfter)
                let d = try await bytes(f, lo, hi - lo + 256)
                let hit = lines(d, partialFirst: lo != f.dataStart).lazy.compactMap(Row.init)
                    .first { $0.type == 2 && $0.id == point && $0.ts == ts }
                last = (ts, (lo + hi) / 2)
                remember(f, point, ts, lo)
                if let r = hit { if !r.value.isNaN { out[ts] = r.value }; break }
            }
        }
        return out
    }

    private func hours(_ a: Int64, _ b: Int64) -> Int {
        guard let da = Self.date(a), let db = Self.date(b) else { return 0 }
        return Int(db.timeIntervalSince(da) / 3600)
    }

    static func date(_ ts: Int64) -> Date? { stamp.date(from: String(ts)) }
    static func ts(_ d: Date) -> Int64 { Int64(stamp.string(from: d))! }

    // MARK: Forecast assembly

    func forecast(point: Int) async throws -> Weather {
        guard let run = run else { throw OGDError.noRun }
        let cal = Calendar.current
        let nextHour = cal.dateInterval(of: .hour, for: Date())!.end   // values are aggregates ending at their timestamp
        let current = Self.ts(nextHour)

        // 3-hour slots starting with the current one; label = start of the period,
        // icon/rain = the 3-hour aggregate ending when the period ends
        let today = cal.startOfDay(for: Date())
        let base = cal.date(byAdding: .hour, value: cal.component(.hour, from: Date()) / 3 * 3, to: today)!
        let slotStarts = (0..<8).map { cal.date(byAdding: .hour, value: $0 * 3, to: base)! }
        let slotEnds = slotStarts.map { Self.ts($0.addingTimeInterval(3 * 3600)) }
        let slotMids = slotStarts.map { Self.ts($0.addingTimeInterval(2 * 3600)) }

        // daily values are stamped 00:00 UTC of the local calendar day
        let dayStamps: [Int64] = (0..<8).map {
            let d = cal.date(byAdding: .day, value: $0, to: today)!
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return Int64(String(format: "%04d%02d%02d0000", c.year!, c.month!, c.day!))!
        }

        async let temps = values(point, .temp, at: [current] + slotMids)
        async let icons = values(point, .icon, at: [current] + slotEnds)
        async let probs = values(point, .rainProb, at: slotEnds)
        async let wind = values(point, .wind, at: [current])
        async let gust = values(point, .gust, at: [current])
        async let dir = values(point, .windDir, at: [current])
        async let dIcon = values(point, .dayIcon, at: dayStamps)
        async let dMin = values(point, .dayMin, at: dayStamps)
        async let dMax = values(point, .dayMax, at: dayStamps)
        async let dRain = values(point, .dayRain, at: dayStamps)
        async let dLo = values(point, .dayRainLo, at: dayStamps)
        async let dHi = values(point, .dayRainHi, at: dayStamps)

        let (t, i, pr) = try await (temps, icons, probs)
        let (w, g, wd) = try await (wind, gust, dir)
        let (di, dn, dx, dr, dl, dh) = try await (dIcon, dMin, dMax, dRain, dLo, dHi)

        guard let temp = t[current] else { throw OGDError.missing("current temperature") }
        let slots = zip(slotStarts, zip(slotMids, slotEnds)).compactMap { start, k -> Slot? in
            guard let ic = i[k.1] else { return nil }
            return Slot(time: start, icon: Int(ic), temp: t[k.0], rainProb: pr[k.1])
        }
        let days = dayStamps.enumerated().compactMap { n, k -> Day? in
            guard let ic = di[k], let lo = dn[k], let hi = dx[k] else { return nil }
            let p = dr[k] ?? 0
            return Day(date: cal.date(byAdding: .day, value: n, to: today)!, icon: Int(ic), tmin: lo, tmax: hi,
                       precip: p, precipMin: dl[k] ?? p, precipMax: dh[k] ?? p)
        }
        return Weather(temp: temp, icon: Int(i[current] ?? i[slotEnds[0]] ?? 5), issued: run,
                       days: days, slots: slots, wind: w[current], gust: g[current],
                       windDir: wd[current].map { Int($0) })
    }
}

// MARK: - Sun times (NOAA / Wikipedia sunrise equation, ±1–2 min)

func sunTimes(lat: Double, lon: Double, on day: Date = Date()) -> (rise: Date, set: Date)? {
    let rad = Double.pi / 180
    let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
    let jd = noon.timeIntervalSince1970 / 86400 + 2440587.5
    let n = (jd - 2451545.0 + 0.0008).rounded()
    let jStar = n - lon / 360
    let m = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
    let c = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
    let lambda = (m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
    let transit = 2451545.0 + jStar + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * lambda * rad)
    let decl = asin(sin(lambda * rad) * sin(23.4397 * rad))
    let cosW = (sin(-0.833 * rad) - sin(lat * rad) * sin(decl)) / (cos(lat * rad) * cos(decl))
    guard abs(cosW) <= 1 else { return nil }
    let w = acos(cosW) / rad / 360
    let toDate = { (j: Double) in Date(timeIntervalSince1970: (j - 2440587.5) * 86400) }
    return (toDate(transit - w), toDate(transit + w))
}
