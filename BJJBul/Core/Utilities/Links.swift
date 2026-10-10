import Foundation

enum Links {
    static func instagram(_ handle: String) -> URL? {
        if handle.hasPrefix("http") { return URL(string: handle) }
        let clean = handle.replacingOccurrences(of: "@", with: "")
        return URL(string: "https://instagram.com/\(clean)")
    }

    static func phone(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if digits.isEmpty { return nil }
        return URL(string: "tel:\(digits)")
    }

    static func web(_ string: String) -> URL? {
        if string.hasPrefix("http") { return URL(string: string) }
        return URL(string: "https://\(string)")
    }

    static func maps(for gym: Gym) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        var items = [URLQueryItem(name: "q", value: gym.name)]
        if gym.hasCoordinates {
            items.append(URLQueryItem(name: "ll", value: "\(gym.latitude),\(gym.longitude)"))
        } else if !gym.address.isEmpty {
            items.append(URLQueryItem(name: "address", value: gym.address))
        }
        components.queryItems = items
        return components.url
    }

    /// 1 = Monday ... 7 = Sunday, localized by the current locale.
    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        let index = weekday % 7
        if index < symbols.count { return symbols[index].capitalized }
        return "\(weekday)"
    }
}

extension Gym {
    var hasCoordinates: Bool { latitude != 0 || longitude != 0 }
}
