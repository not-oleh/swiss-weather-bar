import Foundation

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
