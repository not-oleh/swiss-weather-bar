import Foundation

// MARK: - Weather symbols
// MeteoSwiss pictogram numbers: 1–42 by day, +100 at night. The numbers may be
// reused per the open-data terms; descriptions and emoji here are our own.

func describe(_ icon: Int) -> String {
    let night = icon > 100
    switch night ? icon - 100 : icon {
    case 1: return night ? "clear" : "sunny"
    case 2: return night ? "mostly clear" : "mostly sunny"
    case 3: return "partly cloudy"
    case 4: return "overcast"
    case 5: return "very cloudy"
    case 6, 29, 32: return "sunny spells with showers"
    case 7, 31: return "sunny spells with sleet"
    case 8, 30: return "sunny spells with snow showers"
    case 9: return "cloudy with showers"
    case 10: return "cloudy with sleet"
    case 11: return "cloudy with snow showers"
    case 12, 13, 36: return "sunny spells, thunderstorms possible"
    case 14: return "light rain"
    case 15: return "light sleet"
    case 16: return "light snow"
    case 17: return "rain at times"
    case 18: return "sleet at times"
    case 19: return "snow at times"
    case 20: return "rain"
    case 21: return "sleet"
    case 22: return "heavy snow"
    case 23, 40, 41: return "cloudy, thunderstorms possible"
    case 24, 25, 38: return "thunderstorms"
    case 26, 35: return "high cloud"
    case 27: return "low cloud"
    case 28: return "fog"
    case 33: return "brief sun, frequent rain"
    case 34: return "brief sun, frequent snow"
    case 37, 39, 42: return "thundery snow showers"
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
    ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((Double(deg) / 45).rounded()) % 8]
}

/// Wind direction for VoiceOver ("north-east" rather than "NE").
func spokenCompass(_ deg: Int) -> String {
    ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][Int((Double(deg) / 45).rounded()) % 8]
}
