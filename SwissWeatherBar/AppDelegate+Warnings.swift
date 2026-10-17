import Cocoa

// Weather warnings in the menu (data: Warnings.swift).

extension AppDelegate {

    // MARK: Weather warnings

    @objc func checkWarnings() {
        let p = place
        Task { @MainActor in
            // Skipped because a check is running: that one re-checks the place when done.
            guard await warn.update(place: p.plz, lat: p.lat, lon: p.lon) else { return }
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
        let cal = swissCalendar
        func t(_ d: Date) -> String {
            swissFormatter {
                $0.dateFormat = cal.isDateInToday(d) ? "HH:mm" : cal.isDateInTomorrow(d) ? "'tomorrow' HH:mm" : "EEE HH:mm"
            }.string(from: d)
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
        let hhmm = swissFormatter { $0.dateFormat = "HH:mm" }
        let dated = swissFormatter { $0.dateStyle = .short; $0.timeStyle = .short }
        for w in list {
            let t = w.text
            let issued = swissCalendar.isDateInToday(w.sent) ? hhmm.string(from: w.sent) : dated.string(from: w.sent)
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
        let f = swissFormatter { $0.dateStyle = .medium; $0.timeStyle = .short }
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
}
