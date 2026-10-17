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
                + (failed ? "\n" + tr("Update failed — showing older data") : "")
            item.button?.setAccessibilityLabel(tr("%@, %.0f degrees, %@", place.name, shown(w.temp), describe(w.icon))
                                               + active.map { ", " + levelName($0) + ": " + $0.text.event }.joined()
                                               + (failed ? ", " + tr("update failed") : ""))
        } else {
            item.button?.title = failed ? "⚠︎ " + tr("Weather") : "…"
            item.button?.toolTip = nil
            item.button?.setAccessibilityLabel(failed ? tr("Weather, update failed") : tr("Weather, loading"))
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
            menu.addItem(row("\(emoji(for: w.icon))  \(String(format: "%.1f", locale: .current, shown(w.temp, 1)))°C  \(describe(w.icon))",
                             speech: tr("Now %.1f degrees, %@", shown(w.temp, 1), describe(w.icon))))
            var details: [String] = [], spoken: [String] = []
            if let s = w.wind {
                var t = tr("Wind %.0f km/h", s)
                var v = tr("Wind %.0f kilometres per hour", s)
                if let d = w.windDir { t += " " + compass(d); v += " " + tr("from the %@", spokenCompass(d)) }
                if let g = w.gust { t += tr(", gusts %.0f", g); v += tr(", gusts %.0f", g) }
                details.append(t); spoken.append(v)
            }
            if let sun = sunTimes(lat: place.lat, lon: place.lon) {
                details.append("☀︎ \(hhmm.string(from: sun.rise)) – \(hhmm.string(from: sun.set))")
                spoken.append(tr("sunrise %@, sunset %@", hhmm.string(from: sun.rise), hhmm.string(from: sun.set)))
            }
            if !details.isEmpty {
                menu.addItem(row(details.joined(separator: "   "), speech: spoken.joined(separator: ", ")))
            }
            let issued = cal.isDateInToday(w.issued) ? hhmm.string(from: w.issued)
                : swissFormatter { $0.dateStyle = .medium; $0.timeStyle = .short }.string(from: w.issued)
            // Times are Swiss; say so when the Mac is in another time zone.
            let elsewhere = TimeZone.current.secondsFromGMT(for: now) != swissTime.secondsFromGMT(for: now)
            menu.addItem(row(tr("Forecast issued %@", issued) + (elsewhere ? " · " + tr("Swiss time") : "")
                             + (failed ? "  ·  " + tr("update failed") : ""), secondary: true))
            addWarnings()

            // A forecast from earlier still holds periods that have already ended.
            let slots = w.slots.filter { $0.time.addingTimeInterval(3 * 3600) > now }
            if !slots.isEmpty {
                menu.addItem(.separator())
                menu.addItem(header(tr("Next 24 hours")))
                for s in slots {
                    let time = hhmm.string(from: s.time)
                    let temp = s.temp.map { String(format: "%.0f°", shown($0)) } ?? ""
                    let prob = s.rainProb.map { $0 >= 5 ? String(format: "%.0f%%", $0) : "" } ?? ""
                    var speech = "\(time), \(describe(s.icon))"
                    var tip = describe(s.icon)
                    if let t = s.temp { speech += tr(", %.0f degrees", shown(t)) }
                    if let p = s.rainProb, p >= 5 {
                        speech += tr(", %.0f percent chance of rain", p)
                        tip += tr(", %.0f%% chance of rain", p)
                    }
                    menu.addItem(row("\(time)\t\(emoji(for: s.icon))\t\(temp)\t\(prob)",
                                     tabs: hourTabs, tip: tip, speech: speech, rain: [3]))
                }
            }

            let days = w.days.filter { $0.date >= cal.startOfDay(for: now) }
            if !days.isEmpty {
                menu.addItem(.separator())
                menu.addItem(header(tr("Forecast")))
                let wd = swissFormatter { $0.setLocalizedDateFormatFromTemplate("EEEd") }
                let full = swissFormatter { $0.setLocalizedDateFormatFromTemplate("EEEEdMMMM") }
                for d in days.prefix(7) {
                    let today = cal.isDateInToday(d.date), tomorrow = cal.isDateInTomorrow(d.date)
                    let name = today ? tr("Today") : tomorrow ? tr("Tomorrow") : wd.string(from: d.date)
                    let lo = d.precipMin.rounded(), hi = d.precipMax.rounded()
                    let rain = d.precipMax < 0.1 ? "" : hi < 1 ? "<1 mm"
                        : lo == hi ? String(format: "%.0f mm", hi)
                        : String(format: "%.0f–%.0f mm", lo, hi)
                    let spokenRain = d.precipMax < 0.1 ? "" : hi < 1 ? tr(", less than 1 millimetre of rain")
                        : lo == hi ? tr(hi == 1 ? ", %.0f millimetre of rain" : ", %.0f millimetres of rain", hi)
                        : tr(", %.0f to %.0f millimetres of rain", lo, hi)
                    let speech = tr("%@, %@, %.0f to %.0f degrees", today || tomorrow ? name : full.string(from: d.date),
                                        describe(d.icon), shown(d.tmin), shown(d.tmax)) + spokenRain
                    menu.addItem(row(String(format: "%@\t%@\t%.0f°\t%.0f°\t%@", name, emoji(for: d.icon), shown(d.tmin), shown(d.tmax), rain),
                                     tabs: dayTabs, tip: describe(d.icon) + (rain.isEmpty ? "" : tr(", %@ of rain", rain)),
                                     speech: speech, rain: [4]))
                }
            }
        } else if failed {
            menu.addItem(row(tr("Could not load the forecast — retrying shortly")))
            addWarnings()
        } else {
            menu.addItem(row(tr("Loading…")))
            addWarnings()
        }

        menu.addItem(.separator())
        let here = NSMenuItem(title: tr("Follow My Location"), action: #selector(toggleFollow), keyEquivalent: "")
        here.state = follow ? .on : .off
        here.target = self
        menu.addItem(here)
        if follow, let issue = locationIssue {
            menu.addItem(row(issue == .outside ? tr("Outside Switzerland · showing %@", place.label)
                                               : tr("Location access is off · showing %@", place.label),
                             tip: issue == .outside ? tr("Local forecasts are only available for Swiss postcodes.")
                                                    : tr("Turn it on in System Settings → Privacy & Security → Location Services."),
                             secondary: true))
        }
        let change = NSMenuItem(title: tr("Change Location…"), action: #selector(changeCity), keyEquivalent: "l")
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
            let r = NSMenuItem(title: tr("Recent Locations"), action: nil, keyEquivalent: "")
            r.submenu = sub
            menu.addItem(r)
        }
        let r = NSMenuItem(title: tr("Refresh"), action: #selector(manualRefresh), keyEquivalent: "r")
        r.target = self
        menu.addItem(r)
        menu.addItem(menuBarOptions())
        menu.addItem(.separator())
        let login = NSMenuItem(title: tr("Open at Login"), action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let about = NSMenuItem(title: tr("About %@", appName), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: tr("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.addItem(.separator())
        let src = NSMenuItem(title: tr("Source: MeteoSwiss"), action: #selector(openSource), keyEquivalent: "")
        src.target = self
        src.toolTip = tr("Forecast data from MeteoSwiss Open Government Data (CC BY 4.0)")
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
        add(tr("Weather Icon"), #selector(toggleIcon), on: prefs.showIcon)
        add(tr("Temperature"), #selector(toggleTemp), on: prefs.showTemp)
        sub.addItem(.separator())
        sub.addItem(header(tr("Location")))
        for mode in MenuBarPrefs.LocationMode.allCases {
            add(mode.title, #selector(setLocationMode(_:)), on: prefs.location == mode, tag: mode.rawValue)
        }
        let m = NSMenuItem(title: tr("Menu Bar Display"), action: nil, keyEquivalent: "")
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
        // MeteoAlarm's disclaimer stays in English: their terms ask for this exact text.
        a.informativeText = [
            tr("Weather forecasts for Swiss postcodes in your menu bar."),
            tr("Source: MeteoSwiss. Forecast data is MeteoSwiss Open Government Data, used under CC BY 4.0. This app is an independent project and is not affiliated with or endorsed by MeteoSwiss. Forecasts are provided without any guarantee of accuracy; for official forecasts and warnings see meteoswiss.admin.ch."),
            tr("Weather warnings are issued by MeteoSwiss and come via MeteoAlarm (EUMETNET), www.meteoalarm.org, used under terms equivalent to CC BY 4.0.")
                + " " + meteoAlarmDisclaimer,
        ].joined(separator: "\n\n")
        a.addButton(withTitle: tr("OK"))
        a.addButton(withTitle: tr("Open Data Terms"))
        a.addButton(withTitle: tr("MeteoAlarm Terms"))
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
            a.informativeText = tr("You can add the app manually in System Settings → General → Login Items.")
            a.runModal()
        }
        rebuild()
    }
}
