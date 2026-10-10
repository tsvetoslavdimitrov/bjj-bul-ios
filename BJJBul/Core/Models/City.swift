import Foundation

struct City: Identifiable, Codable, Hashable {
    let id: UUID
    var nameBg: String
    var nameEn: String
    var oblast: String
    var latitude: Double
    var longitude: Double
    var slug: String
}
