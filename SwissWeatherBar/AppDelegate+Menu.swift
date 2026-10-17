import Cocoa
import ServiceManagement

// The menu bar button, the menu and its commands.

extension AppDelegate {

    /// Updates the menu bar button and the menu.
    func rebuild() {
        if let f = fetchedAt, Date().timeIntervalSince(f) > forecastMaxAge { weather = nil }
        if let w = weather {
            var parts: [String] = []
            if prefs.showIcon { parts.append(emoji(for: w.icon)) }
            if prefs.showTemp { parts.append(String(format: "%.0f°", shown(w.temp))) }
            if let loc = prefs.locationText(for: place) { parts.append(loc) }
            if parts.isEmpty { parts = [emoji(for: w.icon)] }   // never leave the menu bar empty
            let active = activeWarnings
            if let top = active.first { parts.insert(top.symbol, at: 0) }
            item.button?.title = parts.joined(separator: " ") + (failed ? " ⚠︎" : "")
            item.button?.toolTip = "\(place.name): \(describe(w.icon))"
                + active.map { "\n\($0.symbol) \($0.text.event)" }.joined()
                + (failed ? "\nUpdate failed — showing older data" : "")
            item.button?.setAccessibilityLabel(String(format: "%@, %.0f degrees, %@", place.name, shown(w.temp), describe(w.icon))
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
        let hhmm = swissFormatter { $0.dateFormat = "HH:mm" }
        let now = Date()
        let cal = swissCalendar
        menu.addItem(header("\(place.label) · \(place.altitude) m"))

        if let w = weather {
            menu.addItem(row("\(emoji(for: w.icon))  \(String(format: "%.1f", shown(w.temp, 1)))°C  \(describe(w.icon))",
                             speech: String(format: "Now %.1f degrees, %@", shown(w.temp, 1), describe(w.icon))))
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
                : swissFormatter { $0.dateStyle = .medium; $0.timeStyle = .short }.string(from: w.issued)
            // Times are Swiss; say so when the Mac is in another time zone.
            let elsewhere = TimeZone.current.secondsFromGMT(for: now) != swissTime.secondsFromGMT(for: now)
            menu.addItem(row("Forecast issued \(issued)" + (elsewhere ? " · Swiss time" : "")
                             + (failed ? "  ·  update failed" : ""), secondary: true))
            addWarnings()

            // A forecast from earlier still holds periods that have already ended.
            let slots = w.slots.filter { $0.time.addingTimeInterval(3 * 3600) > now }
            if !slots.isEmpty {
                menu.addItem(.separator())
                menu.addItem(header("Next 24 hours"))
                for s in slots {
                    let time = hhmm.string(from: s.time)
                    let temp = s.temp.map { String(format: "%.0f°", shown($0)) } ?? ""
                    let prob = s.rainProb.map { $0 >= 5 ? String(format: "%.0f%%", $0) : "" } ?? ""
                    var speech = "\(time), \(describe(s.icon))"
                    var tip = describe(s.icon)
                    if let t = s.temp { speech += String(format: ", %.0f degrees", shown(t)) }
                    if let p = s.rainProb, p >= 5 {
                        speech += String(format: ", %.0f percent chance of rain", p)
                        tip += String(format: ", %.0f%% chance of rain", p)
                    }
                    menu.addItem(row("\(time)\t\(emoji(for: s.icon))\t\(temp)\t\(prob)",
                                     tabs: hourTabs, tip: tip, speech: speech, rain: [3]))
                }
            }

            let days = w.days.filter { $0.date >= cal.startOfDay(for: now) }
            if !days.isEmpty {
                menu.addItem(.separator())
                menu.addItem(header("Forecast"))
                let wd = swissFormatter { $0.dateFormat = "EEE d" }
                let full = swissFormatter { $0.setLocalizedDateFormatFromTemplate("EEEEdMMMM") }
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
                                        describe(d.icon), shown(d.tmin), shown(d.tmax)) + spokenRain
                    menu.addItem(row(String(format: "%@\t%@\t%.0f°\t%.0f°\t%@", name, emoji(for: d.icon), shown(d.tmin), shown(d.tmax), rain),
                                     tabs: dayTabs, tip: describe(d.icon) + (rain.isEmpty ? "" : ", \(rain) of rain"),
                                     speech: speech, rain: [4]))
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
}
