import Cocoa

extension AppDelegate {

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
            popup?.addItem(withTitle: tr("No matches"))
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
        alert.messageText = tr("Choose a location")
        alert.informativeText = tr("Type a place name or postcode, then press Return.")
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
        let field = NSSearchField(frame: NSRect(x: 0, y: 30, width: 300, height: 24))
        field.delegate = self
        field.placeholderString = tr("e.g. Bern or 3011")
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        box.addSubview(field); box.addSubview(pop)
        popup = pop
        matches = []
        alert.accessoryView = box
        alert.addButton(withTitle: tr("Select"))
        alert.addButton(withTitle: tr("Cancel"))
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn, pop.indexOfSelectedItem >= 0,
           pop.indexOfSelectedItem < matches.count {
            select(matches[pop.indexOfSelectedItem])
        }
        popup = nil
    }
}
