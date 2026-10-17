import Cocoa
import CoreLocation
import ServiceManagement

// Swiss Weather Bar — a menu bar forecast for Swiss postcodes.
// Forecast data: Source: MeteoSwiss (Open Government Data, CC BY 4.0).
// Not affiliated with or endorsed by MeteoSwiss.

let appName = "Swiss Weather Bar"
let dataPortal = URL(string: "https://opendatadocs.meteoswiss.ch")!

// MARK: - Places

struct Place: Equatable {
    let name: String
    let plz: Int      // forecast point id: postcode × 100 + suffix, e.g. 800100 = 8001 Zürich
    let altitude: Int
    let lat: Double
    let lon: Double
    var label: String { "\(plz / 100) \(name)" }
}

func loadPlaces() -> [Place] {
    guard let url = Bundle.main.url(forResource: "places", withExtension: "tsv"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap { line in
        guard !line.hasPrefix("#") else { return nil }
        let f = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard f.count == 5, let plz = Int(f[1]), let alt = Int(f[2]),
              let lat = Double(f[3]), let lon = Double(f[4]) else { return nil }
        return Place(name: String(f[0]), plz: plz, altitude: alt, lat: lat, lon: lon)
    }
}

/// Distance in metres (equirectangular approximation, fine at Swiss scale).
func distance(_ c: CLLocationCoordinate2D, _ p: Place) -> Double {
    let dx = (p.lon - c.longitude) * cos(c.latitude * .pi / 180), dy = p.lat - c.latitude
    return (dx * dx + dy * dy).squareRoot() * 111_195
}

/// Nearest place and its distance in metres.
func nearest(to c: CLLocationCoordinate2D, in places: [Place]) -> (Place, Double)? {
    places.map { ($0, distance(c, $0)) }.min { $0.1 < $1.1 }
}

// MARK: - Weather symbols
// MeteoSwiss pictogram numbers: 1–42 by day, +100 at night. The numbers may be
// reused per the open-data terms; descriptions and emoji here are our own.

func describe(_ icon: Int) -> String {
    let night = icon > 100
    switch night ? icon - 100 : icon {
    case 1: return night ? "clear" : "sunny"
    case 2: return night ? "mostly clear" : "mostly sunny"
    case 3: return "partly cloudy"
    case 4: return "overcast"
    case 5: return "very cloudy"
    case 6, 29, 32: return "sunny spells with showers"
    case 7, 31: return "sunny spells with sleet"
    case 8, 30: return "sunny spells with snow showers"
    case 9: return "cloudy with showers"
    case 10: return "cloudy with sleet"
    case 11: return "cloudy with snow showers"
    case 12, 13, 36: return "sunny spells, thunderstorms possible"
    case 14: return "light rain"
    case 15: return "light sleet"
    case 16: return "light snow"
    case 17: return "rain at times"
    case 18: return "sleet at times"
    case 19: return "snow at times"
    case 20: return "rain"
    case 21: return "sleet"
    case 22: return "heavy snow"
    case 23, 40, 41: return "cloudy, thunderstorms possible"
    case 24, 25, 38: return "thunderstorms"
    case 26, 35: return "high cloud"
    case 27: return "low cloud"
    case 28: return "fog"
    case 33: return "brief sun, frequent rain"
    case 34: return "brief sun, frequent snow"
    case 37, 39, 42: return "thundery snow showers"
    default: return "—"
    }
}

func emoji(for icon: Int) -> String {
    let night = icon > 100
    switch night ? icon - 100 : icon {
    case 1: return night ? "🌙" : "☀️"
    case 2: return night ? "🌙" : "🌤"
    case 3: return night ? "☁️" : "⛅️"
    case 4, 5, 35: return "☁️"
    case 26: return night ? "☁️" : "🌥"
    case 27, 28: return "🌫"
    case 6, 29, 32: return night ? "🌧" : "🌦"
    case 9, 14, 17, 20, 33: return "🌧"
    case 7, 10, 15, 18, 21, 31: return "🌨"
    case 8, 11, 16, 19, 22, 30, 34: return "❄️"
    case 12, 13, 36: return night ? "⛈" : "🌩"
    case 23...25, 37...42: return "⛈"
    default: return "☁️"
    }
}

func compass(_ deg: Int) -> String {
    ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((Double(deg) / 45).rounded()) % 8]
}

/// Wind direction for VoiceOver ("north-east" rather than "NE").
func spokenCompass(_ deg: Int) -> String {
    ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][Int((Double(deg) / 45).rounded()) % 8]
}

// MARK: - Menu helpers

/// A non-interactive row. It is drawn by a custom view because AppKit greys out the
/// text of disabled menu items; tab-separated columns line up on the given tab stops.
/// VoiceOver reads the row as one sentence: `speech`, or the text without the tabs.
func row(_ text: String, tabs: [NSTextTab] = [], tip: String? = nil, secondary: Bool = false,
         speech: String? = nil) -> NSMenuItem {
    let inset = rowInset
    let font = secondary ? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                         : NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    let color: NSColor = secondary ? .secondaryLabelColor : .labelColor
    let height: CGFloat = secondary ? 20 : 22
    let view = NSView()
    var maxX: CGFloat = 0
    for (i, c) in text.components(separatedBy: "\t").enumerated() {
        let label = NSTextField(labelWithString: c)
        label.font = font
        label.textColor = color
        label.setAccessibilityElement(false)
        label.sizeToFit()
        let w = label.frame.width
        var x = inset
        if i > 0, i - 1 < tabs.count {
            let s = tabs[i - 1]
            x = inset + s.location - (s.alignment == .right ? w : 0)
        }
        label.frame = NSRect(x: x, y: (height - label.frame.height) / 2, width: w, height: label.frame.height)
        maxX = max(maxX, label.frame.maxX)
        view.addSubview(label)
    }
    view.frame = NSRect(x: 0, y: 0, width: max(260, maxX + inset), height: height)
    view.toolTip = tip      // a menu item with a custom view ignores its own toolTip
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.staticText)
    view.setAccessibilityLabel(speech ?? text.split(separator: "\t").joined(separator: ", "))
    let m = NSMenuItem()
    m.view = view
    return m
}

/// Left edge of the text in standard menu items (after the checkmark column),
/// so custom rows line up with the headers and commands.
let rowInset: CGFloat = 22

func header(_ title: String) -> NSMenuItem {
    if #available(macOS 14, *) { return .sectionHeader(title: title) }
    let m = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
    m.isEnabled = false
    return m
}

// time | icon | temperature | rain chance | drop — "100%" needs its own column
// or it runs into the temperature
let hourTabs = [NSTextTab(textAlignment: .left, location: 52), NSTextTab(textAlignment: .right, location: 112),
                NSTextTab(textAlignment: .right, location: 160), NSTextTab(textAlignment: .left, location: 166)]
let dayTabs = [NSTextTab(textAlignment: .left, location: 84), NSTextTab(textAlignment: .right, location: 144),
               NSTextTab(textAlignment: .right, location: 184), NSTextTab(textAlignment: .right, location: 268)]

// MARK: - Menu bar preferences

struct MenuBarPrefs {
    enum LocationMode: Int, CaseIterable {
        case none, name, postcode, both
        var title: String {
            switch self {
            case .none: return "Hidden"
            case .name: return "Place Name"
            case .postcode: return "Postcode"
            case .both: return "Postcode and Name"
            }
        }
    }
    private let d = UserDefaults.standard

    var showIcon: Bool {
        get { d.object(forKey: "bar.icon") as? Bool ?? true }
        nonmutating set { d.set(newValue, forKey: "bar.icon") }
    }
    var showTemp: Bool {
        get { d.object(forKey: "bar.temp") as? Bool ?? true }
        nonmutating set { d.set(newValue, forKey: "bar.temp") }
    }
    var location: LocationMode {
        get { LocationMode(rawValue: d.integer(forKey: "bar.location")) ?? .none }
        nonmutating set { d.set(newValue.rawValue, forKey: "bar.location") }
    }

    func locationText(for p: Place) -> String? {
        let name = p.name.count > 16 ? String(p.name.prefix(15)) + "…" : p.name
        switch location {
        case .none: return nil
        case .name: return name
        case .postcode: return String(p.plz / 100)
        case .both: return "\(p.plz / 100) \(name)"
        }
    }
}

let prefs = MenuBarPrefs()

// MARK: - Offline cache
// The last forecast is kept on disk so the menu has something to show at launch,
// even when the network is not up yet.

struct CachedForecast: Codable {
    let plz: Int
    let fetchedAt: Date
    let weather: Weather
}

let cacheURL: URL = {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "SwissWeatherBar", isDirectory: true)
    return dir.appendingPathComponent("forecast.json")
}()

func saveCache(_ c: CachedForecast) {
    try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONEncoder().encode(c).write(to: cacheURL, options: .atomic)
}

/// The cached forecast for `plz`, unless it is too old to pass for current conditions.
func loadCache(for plz: Int, maxAge: TimeInterval = 12 * 3600) -> CachedForecast? {
    guard let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(CachedForecast.self, from: d),
          c.plz == plz, Date().timeIntervalSince(c.fetchedAt) < maxAge else { return nil }
    return c
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate,
                         @preconcurrency CLLocationManagerDelegate {   // callbacks arrive on the main thread
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let places = loadPlaces()
    let client = OGDClient()
    let warn = WarningsClient()
    var warnTimer: Timer?
    var place: Place
    var weather: Weather?
    var failed = false
    var loading = false
    var fetchedAt: Date?         // when the forecast for `place` was last downloaded
    var timer: Timer?
    var retry: Timer?
    let locator = CLLocationManager()
    var locating = false
    var locateQuietly = false    // automatic attempt: no error alerts
    let switchMargin = 1_000.0   // metres; see locationManager(_:didUpdateLocations:)
    /// Why "Follow My Location" is not following right now; shown under it in the menu.
    enum LocationIssue { case outside, denied }
    var locationIssue: LocationIssue?

    /// Follow the Mac's location (on by default). Picking a place by hand turns it off.
    var follow: Bool {
        get { UserDefaults.standard.object(forKey: "follow") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "follow") }
    }

    // picker UI state
    var matches: [Place] = []
    var popup: NSPopUpButton?

    var recent: [Int] {
        get { UserDefaults.standard.array(forKey: "recent") as? [Int] ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(6)), forKey: "recent") }
    }

    override init() {
        let saved = UserDefaults.standard.integer(forKey: "plz")
        let all = loadPlaces()
        place = all.first { $0.plz == saved } ?? all.first { $0.plz == 300800 }
            ?? Place(name: "Bern", plz: 300800, altitude: 540, lat: 46.9466, lon: 7.4441)
        super.init()
        locator.delegate = self
        locator.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        if let c = loadCache(for: place.plz) {
            weather = c.weather
            fetchedAt = c.fetchedAt     // refresh() still downloads: the client has no run yet
        }
        menu.delegate = self
        item.menu = menu
        rebuild()
        refresh()
        checkWarnings()
        if follow { locate(quiet: true) }
        // MeteoAlarm's terms allow at most 10 minutes' delay; checking every 5
        // minutes keeps the average delay around 2½ minutes.
        warnTimer = Timer.scheduledTimer(timeInterval: 300, target: self, selector: #selector(checkWarnings),
                                         userInfo: nil, repeats: true)
        // A new forecast run is published hourly; checking every 15 min only costs
        // a few HEAD requests when nothing has changed.
        timer = Timer.scheduledTimer(timeInterval: 900, target: self, selector: #selector(tick),
                                     userInfo: nil, repeats: true)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc func tick() {
        refresh()
        if follow { locate(quiet: true) }
    }

    @objc func didWake() {
        rebuild()       // warnings from before sleep are out of date: hide them
        perform(#selector(afterWake), with: nil, afterDelay: 5)   // network is often not up yet
    }

    @objc func afterWake() {
        tick()
        checkWarnings()
    }

    @objc func refresh() { load(force: false) }
    @objc func manualRefresh() { load(force: true) }

    func load(force: Bool) {
        guard !loading else { return }
        retry?.invalidate()
        loading = true
        let point = place.plz
        // Runs are hourly, so a new run normally moves "now" along; refetch an
        // unchanged run only if it has gone stale (e.g. publication is delayed).
        let stale = fetchedAt.map { Date().timeIntervalSince($0) > 5400 } ?? true
        let client = self.client, current = weather
        Task { @MainActor in
            var result: Weather?
            do {
                let newRun = try await client.updateRun()
                if newRun || force || current == nil || stale {
                    let w = try await client.forecast(point: point)
                    result = w
                    fetchedAt = Date()
                    saveCache(CachedForecast(plz: point, fetchedAt: Date(), weather: w))
                } else {
                    result = current
                }
            } catch {
                NSLog("\(appName): update failed: \(error)")
            }
            finish(result, for: point)
        }
    }

    func finish(_ result: Weather?, for point: Int) {
        loading = false
        guard point == place.plz else { return load(force: true) }   // location changed meanwhile
        if let w = result {
            weather = w; failed = false
        } else {
            failed = true
            retry = Timer.scheduledTimer(timeInterval: 120, target: self, selector: #selector(refresh),
                                         userInfo: nil, repeats: false)
        }
        rebuild()
    }

    func select(_ p: Place, manual: Bool = true) {
        if manual { follow = false }
        place = p
        UserDefaults.standard.set(p.plz, forKey: "plz")
        recent = [p.plz] + recent.filter { $0 != p.plz }
        weather = nil
        fetchedAt = nil
        failed = false
        rebuild()
        load(force: true)
        checkWarnings()
    }

    // MARK: Weather warnings

    @objc func checkWarnings() {
        let p = place
        Task { @MainActor in
            await warn.update(place: p.plz, lat: p.lat, lon: p.lon)
            if warn.matchedPlace != place.plz, !warn.failed { return checkWarnings() }   // place changed meanwhile
            rebuild()
        }
    }

    /// Warnings in force right now, most severe first.
    var activeWarnings: [WeatherWarning] {
        let now = Date()
        return warn.warnings(for: place.plz).filter { $0.onset <= now }
    }

    func period(_ w: WeatherWarning) -> String {
        let cal = Calendar.current
        func t(_ d: Date) -> String {
            let f = DateFormatter()
            f.dateFormat = cal.isDateInToday(d) ? "HH:mm" : cal.isDateInTomorrow(d) ? "'tomorrow' HH:mm" : "EEE HH:mm"
            return f.string(from: d)
        }
        return w.onset <= Date() ? "until \(t(w.expires))" : "\(t(w.onset)) – \(t(w.expires))"
    }

    func addWarnings() {
        guard warn.checkedAt != nil || warn.failed else { return }   // first check still running
        guard warn.isFresh else {
            menu.addItem(link("Weather warnings unavailable · meteoalarm.org", meteoAlarmSite))
            return
        }
        let list = warn.warnings(for: place.plz)
        guard !list.isEmpty else {
            menu.addItem(link("No weather warnings · meteoalarm.org", meteoAlarmSite))
            return
        }
        menu.addItem(.separator())
        menu.addItem(header("Weather Warnings"))
        let hhmm = DateFormatter(); hhmm.dateFormat = "HH:mm"
        for w in list {
            let t = w.text
            let issued = Calendar.current.isDateInToday(w.sent) ? hhmm.string(from: w.sent)
                : DateFormatter.localizedString(from: w.sent, dateStyle: .short, timeStyle: .short)
            let title = NSMutableAttributedString(string: "\(w.symbol) \(t.event)\n",
                                                  attributes: [.font: NSFont.menuFont(ofSize: 0)])
            title.append(NSAttributedString(string: "\(period(w)) · issued \(issued) by \(t.senderName)",
                                            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                                         .foregroundColor: NSColor.secondaryLabelColor]))
            let m = NSMenuItem(title: t.event, action: #selector(showWarning(_:)), keyEquivalent: "")
            m.attributedTitle = title
            m.target = self
            m.representedObject = w.identifier
            m.toolTip = "\(t.headline) — click for the full warning"
            m.setAccessibilityLabel("\(w.colour) warning: \(t.event), \(period(w)), issued \(issued) by \(t.senderName)")
            menu.addItem(m)
        }
        menu.addItem(link("Warnings via MeteoAlarm · meteoalarm.org", meteoAlarmSite))
    }

    func link(_ title: String, _ url: URL) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: #selector(openLink(_:)), keyEquivalent: "")
        m.target = self
        m.representedObject = url
        m.toolTip = meteoAlarmDisclaimer
        return m.withSecondaryStyle()
    }

    @objc func openLink(_ sender: NSMenuItem) {
        if let u = sender.representedObject as? URL { NSWorkspace.shared.open(u) }
    }

    /// The warning as published: the texts unshortened, with the issuing service,
    /// time of issue and MeteoAlarm's disclaimer.
    @objc func showWarning(_ sender: NSMenuItem) {
        guard let w = warn.warnings(for: place.plz).first(where: { $0.identifier == sender.representedObject as? String })
        else { return }
        let t = w.text
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        var body = """
            \(t.event) · \(w.colour.capitalized) warning (level \(w.level))
            Area: \(w.area)
            Valid: \(f.string(from: w.onset)) – \(f.string(from: w.expires))
            Issued: \(f.string(from: w.sent)) by \(t.senderName)
            """
        if !t.description.isEmpty { body += "\n\n" + t.description }
        if !t.instruction.isEmpty, !t.description.contains(t.instruction) { body += "\n\n" + t.instruction }
        body += "\n\nSource: \(t.senderName), via MeteoAlarm (EUMETNET), www.meteoalarm.org.\n\(meteoAlarmDisclaimer)"
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "\(w.symbol) \(t.headline)"
        a.informativeText = body
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Open MeteoAlarm")
        if t.web != nil { a.addButton(withTitle: "Open \(t.senderName)") }
        switch a.runModal() {
        case .alertSecondButtonReturn: NSWorkspace.shared.open(meteoAlarmSite)
        case .alertThirdButtonReturn: if let web = t.web { NSWorkspace.shared.open(web) }
        default: break
        }
    }

    /// Updates the menu bar button and the menu.
    func rebuild() {
        if let w = weather {
            var parts: [String] = []
            if prefs.showIcon { parts.append(emoji(for: w.icon)) }
            if prefs.showTemp { parts.append(String(format: "%.0f°", w.temp.rounded())) }
            if let loc = prefs.locationText(for: place) { parts.append(loc) }
            if parts.isEmpty { parts = [emoji(for: w.icon)] }   // never leave the menu bar empty
            let active = activeWarnings
            if let top = active.first { parts.insert(top.symbol, at: 0) }
            item.button?.title = parts.joined(separator: " ") + (failed ? " ⚠︎" : "")
            item.button?.toolTip = "\(place.name): \(describe(w.icon))"
                + active.map { "\n\($0.symbol) \($0.text.event)" }.joined()
                + (failed ? "\nUpdate failed — showing older data" : "")
            item.button?.setAccessibilityLabel(String(format: "%@, %.0f degrees, %@", place.name, w.temp.rounded(), describe(w.icon))
                                               + active.map { ", \($0.colour) warning: \($0.text.event)" }.joined()
                                               + (failed ? ", update failed" : ""))
        } else {
            item.button?.title = failed ? "⚠︎ Weather" : "…"
            item.button?.toolTip = nil
            item.button?.setAccessibilityLabel(failed ? "Weather, update failed" : "Weather, loading")
        }
        fillMenu()
    }

    /// The menu is also refilled each time it opens, so "Today", the next 24 hours
    /// and sunrise follow the clock even when no new forecast has arrived.
    func menuNeedsUpdate(_ m: NSMenu) {
        fillMenu()
        if let c = warn.checkedAt, Date().timeIntervalSince(c) > 300 { checkWarnings() }   // timer ran late
    }

    func fillMenu() {
        menu.removeAllItems()
        let hhmm = DateFormatter(); hhmm.dateFormat = "HH:mm"
        let now = Date()
        let cal = Calendar.current
        menu.addItem(header("\(place.label) · \(place.altitude) m"))

        if let w = weather {
            menu.addItem(row("\(emoji(for: w.icon))  \(String(format: "%.1f", w.temp))°C  \(describe(w.icon))",
                             speech: String(format: "Now %.1f degrees, %@", w.temp, describe(w.icon))))
            var details: [String] = [], spoken: [String] = []
            if let s = w.wind {
                var t = String(format: "Wind %.0f km/h", s)
                var v = String(format: "Wind %.0f kilometres per hour", s)
                if let d = w.windDir { t += " " + compass(d); v += " from the " + spokenCompass(d) }
                if let g = w.gust { t += String(format: ", gusts %.0f", g); v += String(format: ", gusts %.0f", g) }
                details.append(t); spoken.append(v)
            }
            if let sun = sunTimes(lat: place.lat, lon: place.lon) {
                details.append("☀︎ \(hhmm.string(from: sun.rise)) – \(hhmm.string(from: sun.set))")
                spoken.append("sunrise \(hhmm.string(from: sun.rise)), sunset \(hhmm.string(from: sun.set))")
            }
            if !details.isEmpty {
                menu.addItem(row(details.joined(separator: "   "), speech: spoken.joined(separator: ", ")))
            }
            let issued = cal.isDateInToday(w.issued) ? hhmm.string(from: w.issued)
                : DateFormatter.localizedString(from: w.issued, dateStyle: .medium, timeStyle: .short)
            menu.addItem(row("Forecast issued \(issued)" + (failed ? "  ·  update failed" : ""), secondary: true))
            addWarnings()

            // A forecast from earlier still holds periods that have already ended.
            let slots = w.slots.filter { $0.time.addingTimeInterval(3 * 3600) > now }
            if !slots.isEmpty {
                menu.addItem(.separator())
                menu.addItem(header("Next 24 hours"))
                for s in slots {
                    let time = hhmm.string(from: s.time)
                    let temp = s.temp.map { String(format: "%.0f°", $0) } ?? ""
                    let prob = s.rainProb.map { $0 >= 5 ? String(format: "%.0f%%\t💧", $0) : "" } ?? ""
                    var speech = "\(time), \(describe(s.icon))"
                    if let t = s.temp { speech += String(format: ", %.0f degrees", t) }
                    if let p = s.rainProb, p >= 5 { speech += String(format: ", %.0f percent chance of rain", p) }
                    menu.addItem(row("\(time)\t\(emoji(for: s.icon))\t\(temp)\t\(prob)",
                                     tabs: hourTabs, tip: describe(s.icon), speech: speech))
                }
            }

            let days = w.days.filter { $0.date >= cal.startOfDay(for: now) }
            if !days.isEmpty {
                menu.addItem(.separator())
                menu.addItem(header("Forecast"))
                let wd = DateFormatter(); wd.dateFormat = "EEE d"
                let full = DateFormatter(); full.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
                for d in days.prefix(7) {
                    let today = cal.isDateInToday(d.date), tomorrow = cal.isDateInTomorrow(d.date)
                    let name = today ? "Today" : tomorrow ? "Tomorrow" : wd.string(from: d.date)
                    let lo = d.precipMin.rounded(), hi = d.precipMax.rounded()
                    let rain = d.precipMax < 0.1 ? "" : hi < 1 ? "<1 mm"
                        : lo == hi ? String(format: "%.0f mm", hi)
                        : String(format: "%.0f–%.0f mm", lo, hi)
                    let spokenRain = d.precipMax < 0.1 ? "" : hi < 1 ? ", less than 1 millimetre of rain"
                        : lo == hi ? String(format: hi == 1 ? ", %.0f millimetre of rain" : ", %.0f millimetres of rain", hi)
                        : String(format: ", %.0f to %.0f millimetres of rain", lo, hi)
                    let speech = String(format: "%@, %@, %.0f to %.0f degrees", today || tomorrow ? name : full.string(from: d.date),
                                        describe(d.icon), d.tmin, d.tmax) + spokenRain
                    menu.addItem(row(String(format: "%@\t%@\t%.0f°\t%.0f°\t%@", name, emoji(for: d.icon), d.tmin, d.tmax, rain),
                                     tabs: dayTabs, tip: describe(d.icon), speech: speech))
                }
            }
        } else if failed {
            menu.addItem(row("Could not load the forecast — retrying shortly"))
            addWarnings()
        } else {
            menu.addItem(row("Loading…"))
            addWarnings()
        }

        menu.addItem(.separator())
        let here = NSMenuItem(title: "Follow My Location", action: #selector(toggleFollow), keyEquivalent: "")
        here.state = follow ? .on : .off
        here.target = self
        menu.addItem(here)
        if follow, let issue = locationIssue {
            menu.addItem(row(issue == .outside ? "Outside Switzerland · showing \(place.label)"
                                               : "Location access is off · showing \(place.label)",
                             tip: issue == .outside ? "Local forecasts are only available for Swiss postcodes."
                                                    : "Turn it on in System Settings → Privacy & Security → Location Services.",
                             secondary: true))
        }
        let change = NSMenuItem(title: "Change Location…", action: #selector(changeCity), keyEquivalent: "l")
        change.target = self
        menu.addItem(change)
        let others = recent.filter { $0 != place.plz }.compactMap { plz in places.first { $0.plz == plz } }
        if !others.isEmpty {
            let sub = NSMenu()
            for p in others {
                let m = NSMenuItem(title: p.label, action: #selector(pickRecent(_:)), keyEquivalent: "")
                m.target = self
                m.tag = p.plz
                sub.addItem(m)
            }
            let r = NSMenuItem(title: "Recent Locations", action: nil, keyEquivalent: "")
            r.submenu = sub
            menu.addItem(r)
        }
        let r = NSMenuItem(title: "Refresh", action: #selector(manualRefresh), keyEquivalent: "r")
        r.target = self
        menu.addItem(r)
        menu.addItem(menuBarOptions())
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let about = NSMenuItem(title: "About \(appName)", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.addItem(.separator())
        let src = NSMenuItem(title: "Source: MeteoSwiss", action: #selector(openSource), keyEquivalent: "")
        src.target = self
        src.toolTip = "Forecast data from MeteoSwiss Open Government Data (CC BY 4.0)"
        menu.addItem(src.withSecondaryStyle())
    }

    func menuBarOptions() -> NSMenuItem {
        let sub = NSMenu()
        func add(_ title: String, _ sel: Selector, on: Bool, tag: Int = 0) {
            let m = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            m.target = self
            m.state = on ? .on : .off
            m.tag = tag
            sub.addItem(m)
        }
        add("Weather Icon", #selector(toggleIcon), on: prefs.showIcon)
        add("Temperature", #selector(toggleTemp), on: prefs.showTemp)
        sub.addItem(.separator())
        sub.addItem(header("Location"))
        for mode in MenuBarPrefs.LocationMode.allCases {
            add(mode.title, #selector(setLocationMode(_:)), on: prefs.location == mode, tag: mode.rawValue)
        }
        let m = NSMenuItem(title: "Menu Bar Display", action: nil, keyEquivalent: "")
        m.submenu = sub
        return m
    }

    @objc func toggleIcon() { prefs.showIcon.toggle(); rebuild() }
    @objc func toggleTemp() { prefs.showTemp.toggle(); rebuild() }
    @objc func setLocationMode(_ sender: NSMenuItem) {
        prefs.location = MenuBarPrefs.LocationMode(rawValue: sender.tag) ?? .none
        rebuild()
    }

    @objc func openSource() { NSWorkspace.shared.open(dataPortal) }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = appName
        a.informativeText = """
            Weather forecasts for Swiss postcodes in your menu bar.

            Source: MeteoSwiss. Forecast data is MeteoSwiss Open Government Data, \
            used under CC BY 4.0. This app is an independent project and is not \
            affiliated with or endorsed by MeteoSwiss. Forecasts are provided \
            without any guarantee of accuracy; for official forecasts and warnings \
            see meteoswiss.admin.ch.

            Weather warnings are issued by MeteoSwiss and come via MeteoAlarm \
            (EUMETNET), www.meteoalarm.org, used under terms equivalent to CC BY 4.0. \
            \(meteoAlarmDisclaimer)
            """
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Open Data Terms")
        a.addButton(withTitle: "MeteoAlarm Terms")
        switch a.runModal() {
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://opendatadocs.meteoswiss.ch/general/terms-of-use")!)
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://www.meteoalarm.org/en/live/page/terms-and-conditions")!)
        default: break
        }
    }

    @objc func pickRecent(_ sender: NSMenuItem) {
        if let p = places.first(where: { $0.plz == sender.tag }) { select(p) }
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert(error: error)
            a.informativeText = "You can add the app manually in System Settings → General → Login Items."
            a.runModal()
        }
        rebuild()
    }

    // MARK: Current location

    @objc func toggleFollow() {
        follow.toggle()
        locationIssue = nil
        if follow { locate(quiet: false) }
        rebuild()
    }

    func locate(quiet: Bool) {
        if locating && quiet { return }
        locateQuietly = quiet
        locating = true
        switch locator.authorizationStatus {
        case .notDetermined: locator.requestWhenInUseAuthorization()   // continues in the callback
        case .denied, .restricted: locationFailed("Location access is off for \(appName). Turn it on in System Settings → Privacy & Security → Location Services.", issue: .denied)
        default: locator.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard locating else { return }
        switch m.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: locationFailed("Location access was not granted.", issue: .denied)
        default: m.requestLocation()
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard locating, let c = locs.last?.coordinate else { return }
        locating = false
        guard let (p, dist) = nearest(to: c, in: places), dist < 20_000 else {
            return locationFailed("Your location is outside Switzerland, where local forecasts are not available. Choose a place with Change Location….",
                                  issue: .outside)
        }
        if locationIssue != nil { locationIssue = nil; rebuild() }
        guard p.plz != place.plz else { return }
        // Wi-Fi positioning wobbles by a few hundred metres; near the midpoint between
        // two postcodes that would flip the place (and refetch) on every check.
        // Automatic checks only switch when the new postcode is clearly closer.
        if locateQuietly, distance(c, place) - dist < switchMargin { return }
        select(p, manual: false)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        guard locating else { return }
        locationFailed("Could not determine your location (\(error.localizedDescription)).")
    }

    /// `issue` is a lasting reason (shown in the menu); without one the failure is
    /// treated as temporary and only reported when the user asked.
    func locationFailed(_ msg: String, issue: LocationIssue? = nil) {
        locating = false
        if issue != nil { locationIssue = issue }
        rebuild()
        if locateQuietly { return }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Current location unavailable"
        a.informativeText = msg
        a.runModal()
    }

    // MARK: City picker

    func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    func updateMatches(_ q: String) {
        let query = norm(q.trimmingCharacters(in: .whitespaces))
        if query.isEmpty { matches = [] }
        else if query.allSatisfy(\.isNumber) {
            matches = places.filter { String($0.plz / 100).hasPrefix(query) }
        } else {
            let pre = places.filter { norm($0.name).hasPrefix(query) }
            let sub = places.filter { !norm($0.name).hasPrefix(query) && norm($0.name).contains(query) }
            matches = pre + sub
        }
        matches = Array(matches.prefix(60))
        popup?.removeAllItems()
        if matches.isEmpty, !query.isEmpty {
            popup?.addItem(withTitle: "No matches")
            popup?.isEnabled = false
        } else {
            popup?.addItems(withTitles: matches.map { "\($0.label) (\($0.altitude) m)" })
            popup?.isEnabled = true
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if let f = obj.object as? NSSearchField { updateMatches(f.stringValue) }
    }

    // Return in the search field confirms the dialog instead of being swallowed.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            NSApp.stopModal(withCode: .alertFirstButtonReturn)
            return true
        }
        return false
    }

    @objc func changeCity() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Choose a location"
        alert.informativeText = "Type a place name or postcode, then press Return."
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
        let field = NSSearchField(frame: NSRect(x: 0, y: 30, width: 300, height: 24))
        field.delegate = self
        field.placeholderString = "e.g. Bern or 3011"
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        box.addSubview(field); box.addSubview(pop)
        popup = pop
        matches = []
        alert.accessoryView = box
        alert.addButton(withTitle: "Select")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn, pop.indexOfSelectedItem >= 0,
           pop.indexOfSelectedItem < matches.count {
            select(matches[pop.indexOfSelectedItem])
        }
        popup = nil
    }
}

extension NSMenuItem {
    func withSecondaryStyle() -> NSMenuItem {
        let a = NSMutableAttributedString(attributedString: attributedTitle ?? NSAttributedString(string: title))
        a.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                         .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)],
                        range: NSRange(location: 0, length: a.length))
        attributedTitle = a
        return self
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { AppDelegate() }   // top-level code runs on the main thread
app.delegate = delegate
app.run()
