import Cocoa
import CoreLocation

let appName = "Swiss Weather Bar"
let dataPortal = URL(string: "https://opendatadocs.meteoswiss.ch")!

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate,
                         @preconcurrency CLLocationManagerDelegate {   // callbacks arrive on the main thread
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let places: [Place]
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
        places = all
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
}
