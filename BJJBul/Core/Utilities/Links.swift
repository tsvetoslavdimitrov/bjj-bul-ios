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

extension Links {
    /// International digits without "+", e.g. "0896454641" -> "359896454641".
    static func internationalDigits(_ phone: String) -> String? {
        var digits = phone.filter { $0.isNumber }
        if phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") {
            return digits.isEmpty ? nil : digits
        }
        if digits.hasPrefix("00") {
            digits = String(digits.dropFirst(2))
        } else if digits.hasPrefix("0") {
            digits = "359" + String(digits.dropFirst())
        }
        return digits.count >= 8 ? digits : nil
    }

    static func whatsApp(_ phone: String) -> URL? {
        guard let digits = internationalDigits(phone) else { return nil }
        return URL(string: "https://wa.me/\(digits)")
    }

    static func viber(_ phone: String) -> URL? {
        guard let digits = internationalDigits(phone) else { return nil }
        return URL(string: "viber://chat?number=%2B\(digits)")
    }

    static func instagramDM(_ handle: String) -> URL? {
        var clean = handle
        if let url = URL(string: handle), url.host?.contains("instagram.com") == true {
            clean = url.pathComponents.filter { $0 != "/" }.first ?? ""
        }
        clean = clean.replacingOccurrences(of: "@", with: "")
        if clean.isEmpty { return nil }
        return URL(string: "https://ig.me/m/\(clean)")
    }
}

extension Gym {
    var hasCoordinates: Bool { latitude != 0 || longitude != 0 }
}
