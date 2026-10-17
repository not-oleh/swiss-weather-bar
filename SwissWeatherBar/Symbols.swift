import Foundation

// MARK: - Weather symbols
// MeteoSwiss pictogram numbers: 1–42 by day, +100 at night. The numbers may be
// reused per the open-data terms; descriptions and emoji here are our own.

func describe(_ icon: Int) -> String {
    let night = icon > 100
    switch night ? icon - 100 : icon {
    case 1: return night ? tr("clear") : tr("sunny")
    case 2: return night ? tr("mostly clear") : tr("mostly sunny")
    case 3: return tr("partly cloudy")
    case 4: return tr("overcast")
    case 5: return tr("very cloudy")
    case 6, 29, 32: return tr("sunny spells with showers")
    case 7, 31: return tr("sunny spells with sleet")
    case 8, 30: return tr("sunny spells with snow showers")
    case 9: return tr("cloudy with showers")
    case 10: return tr("cloudy with sleet")
    case 11: return tr("cloudy with snow showers")
    case 12, 13, 36: return tr("sunny spells, thunderstorms possible")
    case 14: return tr("light rain")
    case 15: return tr("light sleet")
    case 16: return tr("light snow")
    case 17: return tr("rain at times")
    case 18: return tr("sleet at times")
    case 19: return tr("snow at times")
    case 20: return tr("rain")
    case 21: return tr("sleet")
    case 22: return tr("heavy snow")
    case 23, 40, 41: return tr("cloudy, thunderstorms possible")
    case 24, 25, 38: return tr("thunderstorms")
    case 26, 35: return tr("high cloud")
    case 27: return tr("low cloud")
    case 28: return tr("fog")
    case 33: return tr("brief sun, frequent rain")
    case 34: return tr("brief sun, frequent snow")
    case 37, 39, 42: return tr("thundery snow showers")
    default: return "—"
    }
}

func emoji(for icon: Int) -> String {
    let night = icon > 100
    switch night ? icon - 100 : icon {
    case 1: return night ? "🌙" : "☀️"
    case 2: return night ? "🌙" : "🌤"
    case 3: return night ? "☁️" : "⛅️"
    case 4, 5, 35: return "☁️"
    case 26: return night ? "☁️" : "🌥"
    case 27, 28: return "🌫"
    case 6, 29, 32: return night ? "🌧" : "🌦"
    case 9, 14, 17, 20, 33: return "🌧"
    case 7, 10, 15, 18, 21, 31: return "🌨"
    case 8, 11, 16, 19, 22, 30, 34: return "❄️"
    case 12, 13, 36: return night ? "⛈" : "🌩"
    case 23...25, 37...42: return "⛈"
    default: return "☁️"
    }
}

func compass(_ deg: Int) -> String {
    tr("N NE E SE S SW W NW").split(separator: " ").map(String.init)[Int((Double(deg) / 45).rounded()) % 8]
}

/// Wind direction for VoiceOver ("north-east" rather than "NE").
func spokenCompass(_ deg: Int) -> String {
    tr("north|north-east|east|south-east|south|south-west|west|north-west").split(separator: "|")
        .map(String.init)[Int((Double(deg) / 45).rounded()) % 8]
}
