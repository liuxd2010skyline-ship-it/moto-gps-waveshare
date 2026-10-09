import Foundation
import MotoNavigationCore

enum BaiduNavigationError: LocalizedError {
    case setupRequired
    case invalidResult
    case ridingDistanceLimit

    var errorDescription: String? {
        switch self {
        case .setupRequired: "请在首页“百度地图配置”中同意隐私说明并填写 iOS AK"
        case .invalidResult: "百度地图没有返回可用路线，请换一个目的地重试"
        case .ridingDistanceLimit: "骑行路线起终点直线距离不能超过 100 公里，请选择更近的终点"
        }
    }
}

private struct BaiduCoordinate: Decodable {
    let longitude: Double
    let latitude: Double

    var gcj02: GCJ02Point { GCJ02Point(longitudeDeg: longitude, latitudeDeg: latitude) }
    var isValid: Bool {
        longitude.isFinite && latitude.isFinite &&
            (-180 ... 180).contains(longitude) && (-90 ... 90).contains(latitude) &&
            (longitude != 0 || latitude != 0)
    }
}

private struct BaiduPlace: Decodable {
    let id: String
    let name: String
    let address: String
    let city: String
    let district: String
    let location: BaiduCoordinate
}

private struct BaiduStep: Decodable {
    let offset: Double
    let startIndex: Int
    let endIndex: Int
    let road: String
    let instruction: String
}

private struct BaiduTraffic: Decodable {
    let start: Double
    let end: Double
    let status: Int
}

private struct BaiduRoute: Decodable {
    let distance: Double
    let duration: Int
    let points: [BaiduCoordinate]
    let steps: [BaiduStep]
    let traffic: [BaiduTraffic]
}

/// The SDK itself remains on the main thread. Swift navigation code sees only
/// coordinates and route data, never Baidu SDK objects or a gateway URL.
@MainActor
private final class BaiduMapClient {
    static let shared = BaiduMapClient()

    private func start() async throws {
        guard UserDefaults.standard.bool(forKey: BaiduMapSetup.privacyKey),
              let ak = UserDefaults.standard.string(forKey: BaiduMapSetup.akKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !ak.isEmpty
        else { throw BaiduNavigationError.setupRequired }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            BaiduMapBridge.shared().authorize(withAK: ak) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func places(_ keywords: String, near origin: WGS84Point?) async throws -> [BaiduPlace] {
        try await start()
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            BaiduMapBridge.shared().searchPlaces(
                keywords,
                nearLatitude: origin?.latitudeDeg ?? 999,
                nearLongitude: origin?.longitudeDeg ?? 999
            ) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: BaiduNavigationError.invalidResult) }
            }
        }
        return try JSONDecoder().decode([BaiduPlace].self, from: data)
    }

    func routes(_ request: RouteRequest, multiple: Bool) async throws -> [BaiduRoute] {
        try await start()
        if request.routeMode != .driving,
           Self.distanceM(from: request.origin, to: request.destination) > 100_000 {
            throw BaiduNavigationError.ridingDistanceLimit
        }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let completion: BaiduMapDataCompletion = { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: BaiduNavigationError.invalidResult) }
            }
            switch request.routeMode {
            case .driving:
                BaiduMapBridge.shared().drivingRoutes(
                    fromLatitude: request.origin.latitudeDeg,
                    longitude: request.origin.longitudeDeg,
                    destinationLatitude: request.destination.latitudeDeg,
                    longitude: request.destination.longitudeDeg,
                    destinationUID: request.destinationPOIID,
                    multiple: multiple,
                    completion: completion
                )
            case .cycling, .electricBicycle:
                BaiduMapBridge.shared().ridingRoutes(
                    fromLatitude: request.origin.latitudeDeg,
                    longitude: request.origin.longitudeDeg,
                    destinationLatitude: request.destination.latitudeDeg,
                    longitude: request.destination.longitudeDeg,
                    electricBike: request.routeMode == .electricBicycle,
                    completion: completion
                )
            }
        }
        return try JSONDecoder().decode([BaiduRoute].self, from: data)
    }

    private static func distanceM(from start: WGS84Point, to end: WGS84Point) -> Double {
        let startLatitude = start.latitudeDeg * .pi / 180
        let endLatitude = end.latitudeDeg * .pi / 180
        let latitudeDelta = endLatitude - startLatitude
        let longitudeDelta = (end.longitudeDeg - start.longitudeDeg) * .pi / 180
        let haversine = pow(sin(latitudeDelta / 2), 2) +
            cos(startLatitude) * cos(endLatitude) * pow(sin(longitudeDelta / 2), 2)
        return 12_742_000 * asin(sqrt(min(1, max(0, haversine))))
    }
}

enum BaiduMapSetup {
    static let privacyKey = "MotoGPS.BaiduPrivacyAccepted.v1"
    static let akKey = "MotoGPS.BaiduIOSAK.v1"
}

final class BaiduPlaceProvider: @unchecked Sendable {
    func search(keywords: String, near origin: WGS84Point? = nil) async throws -> [PlaceSearchResult] {
        let places = try await BaiduMapClient.shared.places(keywords, near: origin)
        try Task.checkCancellation()
        return places.filter { $0.location.isValid }.map { place in
            let point = ChinaCoordinateTransform.gcj02ToWGS84(place.location.gcj02)
            return PlaceSearchResult(
                id: place.id,
                name: place.name,
                address: place.address,
                city: place.city,
                district: place.district,
                displayArea: [place.city, place.district].filter { !$0.isEmpty }.joined(separator: " · "),
                location: point,
                distanceM: origin.map { Self.distance(from: $0, to: point) }
            )
        }
    }

    private static func distance(from start: WGS84Point, to end: WGS84Point) -> Double {
        let lat1 = start.latitudeDeg * .pi / 180
        let lat2 = end.latitudeDeg * .pi / 180
        let latDelta = lat2 - lat1
        let lonDelta = (end.longitudeDeg - start.longitudeDeg) * .pi / 180
        let h = pow(sin(latDelta / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(lonDelta / 2), 2)
        return 12_742_000 * asin(sqrt(min(1, max(0, h))))
    }
}

final class BaiduRouteProvider: NavigationRouteProviding, @unchecked Sendable {
    func route(for request: RouteRequest) async throws -> RouteEnvelope {
        guard let first = try await routeOptions(for: request, multiple: false).first else {
            throw BaiduNavigationError.invalidResult
        }
        return RouteEnvelope(requestID: request.requestID, route: first)
    }

    func routeOptions(for request: RouteRequest) async throws -> [RoutePlan] {
        try await routeOptions(for: request, multiple: true)
    }

    private func routeOptions(for request: RouteRequest, multiple: Bool) async throws -> [RoutePlan] {
        let routes = try await BaiduMapClient.shared.routes(request, multiple: multiple)
        try Task.checkCancellation()
        let plans = routes.prefix(3).compactMap { route -> RoutePlan? in
            guard route.points.count >= 2, route.points.allSatisfy(\.isValid),
                  route.distance.isFinite, route.distance > 0, route.duration > 0
            else { return nil }
            let finalManeuvers = RouteStepGuidance.maneuvers(
                points: route.points.map(\.gcj02),
                steps: route.steps.map { RouteGuidanceStep(
                    startIndex: $0.startIndex, endIndex: $0.endIndex,
                    instruction: $0.instruction, road: $0.road
                ) },
                totalDistanceM: route.distance
            )
            let traffic = route.traffic.compactMap { segment -> TrafficSegment? in
                guard segment.start.isFinite, segment.end.isFinite,
                      segment.start >= 0, segment.end > segment.start,
                      segment.start < route.distance
                else { return nil }
                return TrafficSegment(
                    startOffsetM: segment.start,
                    endOffsetM: min(segment.end, route.distance),
                    level: Self.trafficLevel(segment.status)
                )
            }
            return RoutePlan(
                routeID: request.previousRouteID.flatMap { !request.isReroute ? $0 : nil }
                    ?? "baidu-\(UUID().uuidString)",
                provider: "baidu-ios-map-sdk",
                generatedAtMs: UInt64(Date().timeIntervalSince1970 * 1_000),
                totalDistanceM: route.distance,
                totalDurationS: route.duration,
                polyline: route.points.map(\.gcj02),
                maneuvers: finalManeuvers,
                traffic: traffic
            )
        }
        guard !plans.isEmpty else { throw BaiduNavigationError.invalidResult }
        return plans
    }

    private static func trafficLevel(_ status: Int) -> TrafficLevel {
        switch status {
        case 1: .freeFlow
        case 2: .slow
        case 3: .congested
        case 4: .severe
        default: .unknown
        }
    }
}
