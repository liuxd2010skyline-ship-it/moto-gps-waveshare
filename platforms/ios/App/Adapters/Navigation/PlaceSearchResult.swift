import Foundation
import MotoNavigationCore

struct PlaceSearchResult: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let address: String
    let city: String
    let district: String
    let displayArea: String
    let location: WGS84Point
    let distanceM: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, address, city, district, location
        case displayArea = "display_area"
        case distanceM = "distance_m"
    }
}
