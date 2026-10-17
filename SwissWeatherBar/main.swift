import Cocoa

// Swiss Weather Bar — a menu bar forecast for Swiss postcodes.
// Forecast data: Source: MeteoSwiss (Open Government Data, CC BY 4.0).
// Not affiliated with or endorsed by MeteoSwiss.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { AppDelegate() }   // top-level code runs on the main thread
app.delegate = delegate
app.run()
