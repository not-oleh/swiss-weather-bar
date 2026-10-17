import Foundation

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

/// After this long without a successful download a forecast is no longer shown:
/// its "current" temperature would be misleading.
let forecastMaxAge: TimeInterval = 12 * 3600

/// The cached forecast for `plz`, unless it is too old to pass for current conditions.
func loadCache(for plz: Int, maxAge: TimeInterval = forecastMaxAge) -> CachedForecast? {
    guard let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(CachedForecast.self, from: d),
          c.plz == plz, Date().timeIntervalSince(c.fetchedAt) < maxAge else { return nil }
    return c
}
