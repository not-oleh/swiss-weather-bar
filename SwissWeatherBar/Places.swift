import Foundation
import CoreLocation

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
