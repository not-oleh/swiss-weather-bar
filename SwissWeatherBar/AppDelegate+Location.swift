import Cocoa
import CoreLocation

extension AppDelegate {

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
}
