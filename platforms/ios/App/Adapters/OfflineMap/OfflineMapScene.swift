import Foundation

struct OfflineMapPointE6: Codable, Equatable, Hashable, Sendable {
    let latitudeE6: Int32
    let longitudeE6: Int32

    init(latitudeE6: Int32, longitudeE6: Int32) {
        self.latitudeE6 = latitudeE6
        self.longitudeE6 = longitudeE6
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        latitudeE6 = try values.decode(Int32.self)
        longitudeE6 = try values.decode(Int32.self)
        guard values.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: values,
                debugDescription: "MapScene point must contain exactly latitudeE6 and longitudeE6"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(latitudeE6)
        try values.encode(longitudeE6)
    }
}

struct OfflineMapRoad: Codable, Equatable, Sendable {
    let osmWayID: Int64?
    let roadClass: String
    let points: [OfflineMapPointE6]

    private enum CodingKeys: String, CodingKey {
        case osmWayID = "osm_way_id"
        case roadClass = "class"
        case points = "points_e6"
    }
}

struct OfflineMapBuilding: Codable, Equatable, Sendable {
    let osmWayID: Int64?
    let name: String?
    let buildingClass: String
    let points: [OfflineMapPointE6]

    private enum CodingKeys: String, CodingKey {
        case osmWayID = "osm_way_id"
        case name
        case buildingClass = "class"
        case points = "points_e6"
    }
}

struct OfflineMapSource: Codable, Equatable, Sendable {
    let provider: String
    let licence: String
    let attributionURL: String
    let retrievedAt: String
    let bboxWGS84: [Double]?

    private enum CodingKeys: String, CodingKey {
        case provider
        case licence
        case attributionURL = "attribution_url"
        case retrievedAt = "retrieved_at"
        case bboxWGS84 = "bbox_wgs84"
    }
}

struct OfflineMapSceneDocument: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let coordinateSystem: String
    let sceneRevision: UInt32
    let viewOrigin: OfflineMapPointE6
    let radiusM: UInt16
    let roads: [OfflineMapRoad]
    let buildings: [OfflineMapBuilding]
    let source: OfflineMapSource

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case coordinateSystem = "coordinate_system"
        case sceneRevision = "scene_revision"
        case viewOrigin = "view_origin_e6"
        case radiusM = "radius_m"
        case roads
        case buildings
        case source
    }

    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, value.coordinateSystem == "GCJ-02" else {
            throw OfflineMapSceneError.unsupportedFormat
        }
        guard value.roads.count <= 24,
              value.roads.reduce(0, { $0 + $1.points.count }) <= 192,
              value.buildings.count <= 48,
              value.buildings.reduce(0, { $0 + $1.points.count }) <= 240,
              value.roads.allSatisfy({ $0.points.count >= 2 }),
              value.buildings.allSatisfy({
                  $0.points.count >= 3 && $0.points.first != $0.points.last
              })
        else { throw OfflineMapSceneError.capacityExceeded }
        return value
    }
}

enum OfflineMapSceneError: Error, Equatable {
    case resourceMissing
    case unsupportedFormat
    case capacityExceeded
}

struct OfflineMapSceneWindow: Equatable, Sendable {
    let revision: UInt32
    let origin: OfflineMapPointE6
    let radiusM: UInt16
    let roads: [OfflineMapRoad]
    let buildings: [OfflineMapBuilding]
}

protocol OfflineMapSceneQuerying: Sendable {
    func query(
        around origin: OfflineMapPointE6,
        radiusM: UInt16,
        revision: UInt32
    ) -> OfflineMapSceneWindow
}

/// Source-independent geometry selector shared by offline SQLite and tiles.
/// It has no platform/SQLite dependency and is exercised by portable Swift CI.
struct InMemoryOfflineMapSceneIndex: OfflineMapSceneQuerying {
    private struct Bounds: Sendable {
        let minimumLatitudeE6: Int32
        let maximumLatitudeE6: Int32
        let minimumLongitudeE6: Int32
        let maximumLongitudeE6: Int32

        init(points: [OfflineMapPointE6]) {
            minimumLatitudeE6 = points.map(\.latitudeE6).min() ?? 0
            maximumLatitudeE6 = points.map(\.latitudeE6).max() ?? 0
            minimumLongitudeE6 = points.map(\.longitudeE6).min() ?? 0
            maximumLongitudeE6 = points.map(\.longitudeE6).max() ?? 0
        }

        func intersects(origin: OfflineMapPointE6, radiusM: Double) -> Bool {
            let metresPerLatitudeE6 = 111_195.0 / 1_000_000
            let latitudeRadians = Double(origin.latitudeE6) / 1_000_000 * .pi / 180
            let metresPerLongitudeE6 = metresPerLatitudeE6 * cos(latitudeRadians)
            let nearestLatitude = min(max(origin.latitudeE6, minimumLatitudeE6), maximumLatitudeE6)
            let nearestLongitude = min(max(origin.longitudeE6, minimumLongitudeE6), maximumLongitudeE6)
            let northM = Double(nearestLatitude - origin.latitudeE6) * metresPerLatitudeE6
            let eastM = Double(nearestLongitude - origin.longitudeE6) * metresPerLongitudeE6
            return hypot(northM, eastM) <= radiusM
        }
    }

    private struct IndexedRoad: Sendable {
        let value: OfflineMapRoad
        let bounds: Bounds
    }

    private struct IndexedBuilding: Sendable {
        let value: OfflineMapBuilding
        let bounds: Bounds
    }

    private let roads: [IndexedRoad]
    private let buildings: [IndexedBuilding]

    init(document: OfflineMapSceneDocument) {
        roads = document.roads.compactMap {
            let points = Self.cleanPoints($0.points, ring: false)
            guard points.count >= 2 else { return nil }
            let value = OfflineMapRoad(osmWayID: $0.osmWayID, roadClass: $0.roadClass, points: points)
            return IndexedRoad(value: value, bounds: Bounds(points: points))
        }
        buildings = document.buildings.compactMap {
            let points = Self.cleanPoints($0.points, ring: true)
            guard points.count >= 3, Set(points).count == points.count else { return nil }
            let value = OfflineMapBuilding(osmWayID: $0.osmWayID, name: $0.name,
                                          buildingClass: $0.buildingClass, points: points)
            return IndexedBuilding(value: value, bounds: Bounds(points: points))
        }
    }

    func query(
        around origin: OfflineMapPointE6,
        radiusM: UInt16,
        revision: UInt32
    ) -> OfflineMapSceneWindow {
        let radius = Double(max(500, min(800, radiusM)))
        guard (-85_000_000...85_000_000).contains(origin.latitudeE6),
              (-180_000_000...180_000_000).contains(origin.longitudeE6) else {
            return OfflineMapSceneWindow(revision: revision, origin: origin,
                                         radiusM: UInt16(radius), roads: [], buildings: [])
        }
        let roadCandidates = roads
            .filter { $0.bounds.intersects(origin: origin, radiusM: radius) }
            .flatMap { indexed in
                Self.clippedRuns(indexed.value, origin: origin, radiusM: radius).map { run in
                    (
                        road: run,
                        importance: Self.roadImportance(run.roadClass),
                        distanceM: Self.minimumDistanceM(run.points, from: origin)
                    )
                }
            }
            .sorted {
                if $0.importance != $1.importance { return $0.importance < $1.importance }
                if $0.distanceM != $1.distanceM { return $0.distanceM < $1.distanceM }
                return ($0.road.osmWayID ?? .max) < ($1.road.osmWayID ?? .max)
            }

        var selectedRoads: [OfflineMapRoad] = []
        var roadKeys: Set<[OfflineMapPointE6]> = []
        var roadPointCount = 0
        for candidate in roadCandidates {
            guard selectedRoads.count < 24 else { break }
            guard roadPointCount + candidate.road.points.count <= 192 else { continue }
            guard roadKeys.insert(Self.canonicalLine(candidate.road.points)).inserted else { continue }
            selectedRoads.append(candidate.road)
            roadPointCount += candidate.road.points.count
        }

        let buildingCandidates = buildings
            .filter { $0.bounds.intersects(origin: origin, radiusM: radius) }
            .filter {
                Self.polygonIntersects($0.value.points, origin: origin, radiusM: radius)
            }
            .filter { indexed in
                // Keep the complete ring; never truncate then close it across
                // a missing wing. Extremely large/off-range footprints cannot
                // be encoded by the v1 relative-coordinate contract.
                indexed.value.points.allSatisfy {
                    abs(Int64($0.latitudeE6) - Int64(origin.latitudeE6)) <= 100_000 &&
                    abs(Int64($0.longitudeE6) - Int64(origin.longitudeE6)) <= 100_000
                }
            }
            .map { indexed in
                let ring = indexed.value.points
                let distance = Self.minimumDistanceM(ring + [ring[0]], from: origin)
                let area = Self.polygonAreaM2(indexed.value.points, around: origin)
                // Larger footprints remain visible a little farther away, while
                // nearby buildings still dominate the tiny round viewport.
                let visualScore = distance - min(150, sqrt(area) * 0.75)
                return (building: indexed.value, visualScore: visualScore, areaM2: area)
            }
            .sorted {
                if $0.visualScore != $1.visualScore { return $0.visualScore < $1.visualScore }
                if $0.areaM2 != $1.areaM2 { return $0.areaM2 > $1.areaM2 }
                return ($0.building.osmWayID ?? .max) < ($1.building.osmWayID ?? .max)
            }

        var selectedBuildings: [OfflineMapBuilding] = []
        var buildingKeys: Set<[OfflineMapPointE6]> = []
        var buildingPointCount = 0
        for candidate in buildingCandidates {
            guard selectedBuildings.count < 48 else { break }
            guard buildingPointCount + candidate.building.points.count <= 240 else { continue }
            guard candidate.areaM2 > 0.5,
                  buildingKeys.insert(Self.canonicalRing(candidate.building.points)).inserted else { continue }
            selectedBuildings.append(candidate.building)
            buildingPointCount += candidate.building.points.count
        }

        return OfflineMapSceneWindow(
            revision: revision,
            origin: origin,
            radiusM: UInt16(radius),
            roads: selectedRoads,
            buildings: selectedBuildings
        )
    }

    private static func clippedRuns(
        _ road: OfflineMapRoad,
        origin: OfflineMapPointE6,
        radiusM: Double
    ) -> [OfflineMapRoad] {
        guard road.points.count >= 2 else { return [] }
        var result: [OfflineMapRoad] = []
        var run: [OfflineMapPointE6] = []
        func finishRun() {
            if run.count >= 2 {
                result.append(OfflineMapRoad(osmWayID: road.osmWayID,
                                            roadClass: road.roadClass, points: run))
            }
            run.removeAll(keepingCapacity: true)
        }
        for index in 1 ..< road.points.count {
            let start = road.points[index - 1]
            let end = road.points[index]
            guard let (a, b) = clippedSegment(start, end, origin: origin, radiusM: radiusM) else {
                finishRun()
                continue
            }
            // An outside excursion must not join two boundary intersections
            // into a new road across empty space.
            if !run.isEmpty && run.last != a { finishRun() }
            if run.isEmpty { run.append(a) }
            if run.last != b { run.append(b) }
            if b != end { finishRun() }
        }
        finishRun()
        return result
    }

    private static func clippedSegment(_ start: OfflineMapPointE6, _ end: OfflineMapPointE6,
                                       origin: OfflineMapPointE6, radiusM: Double)
        -> (OfflineMapPointE6, OfflineMapPointE6)? {
        let (ax, ay) = localMetres(start, around: origin)
        let (bx, by) = localMetres(end, around: origin)
        let dx = bx - ax, dy = by - ay
        let a = dx * dx + dy * dy
        guard a > 0 else { return nil }
        let b = 2 * (ax * dx + ay * dy)
        let c = ax * ax + ay * ay - radiusM * radiusM
        let discriminant = b * b - 4 * a * c
        guard discriminant > 0 else { return nil }
        let root = sqrt(discriminant)
        let enter = max(0, (-b - root) / (2 * a))
        let leave = min(1, (-b + root) / (2 * a))
        guard enter < leave else { return nil }
        func interpolate(_ t: Double) -> OfflineMapPointE6 {
            OfflineMapPointE6(
                latitudeE6: Int32((Double(start.latitudeE6) +
                                  Double(Int64(end.latitudeE6) - Int64(start.latitudeE6)) * t).rounded()),
                longitudeE6: Int32((Double(start.longitudeE6) +
                                   Double(Int64(end.longitudeE6) - Int64(start.longitudeE6)) * t).rounded()))
        }
        let first = enter == 0 ? start : interpolate(enter)
        let last = leave == 1 ? end : interpolate(leave)
        return first == last ? nil : (first, last)
    }

    private static func cleanPoints(_ points: [OfflineMapPointE6], ring: Bool) -> [OfflineMapPointE6] {
        guard points.allSatisfy({ (-85_000_000...85_000_000).contains($0.latitudeE6) &&
            (-180_000_000...180_000_000).contains($0.longitudeE6) }) else { return [] }
        var result: [OfflineMapPointE6] = []
        for point in points where result.last != point { result.append(point) }
        if ring && result.count > 1 && result.first == result.last { result.removeLast() }
        return result
    }

    private static func isBefore(_ a: OfflineMapPointE6, _ b: OfflineMapPointE6) -> Bool {
        a.latitudeE6 == b.latitudeE6 ? a.longitudeE6 < b.longitudeE6 : a.latitudeE6 < b.latitudeE6
    }

    private static func canonicalLine(_ points: [OfflineMapPointE6]) -> [OfflineMapPointE6] {
        guard let first = points.first, let last = points.last else { return points }
        return isBefore(last, first) ? Array(points.reversed()) : points
    }

    private static func canonicalRing(_ points: [OfflineMapPointE6]) -> [OfflineMapPointE6] {
        guard let minimum = points.indices.min(by: { isBefore(points[$0], points[$1]) }) else { return points }
        let rotated = Array(points[minimum...]) + Array(points[..<minimum])
        if rotated.count > 2 && isBefore(rotated.last!, rotated[1]) {
            return [rotated[0]] + Array(rotated.dropFirst().reversed())
        }
        return rotated
    }

    private static func polygonIntersects(
        _ points: [OfflineMapPointE6],
        origin: OfflineMapPointE6,
        radiusM: Double
    ) -> Bool {
        guard points.count >= 3 else { return false }
        if points.contains(where: { distanceM(origin, $0) <= radiusM }) { return true }
        for index in points.indices {
            if segmentDistanceM(origin, points[index], points[(index + 1) % points.count]) <= radiusM {
                return true
            }
        }
        return pointInPolygon(origin, points)
    }

    private static func roadImportance(_ roadClass: String) -> Int {
        switch roadClass {
        case "primary": 0
        case "secondary": 1
        case "motorway": 2
        case "residential": 3
        case "service": 4
        default: 5
        }
    }

    private static func minimumDistanceM(
        _ points: [OfflineMapPointE6],
        from origin: OfflineMapPointE6
    ) -> Double {
        guard !points.isEmpty else { return .infinity }
        if points.count == 1 { return distanceM(origin, points[0]) }
        return (1 ..< points.count).reduce(.infinity) { minimum, index in
            min(minimum, segmentDistanceM(origin, points[index - 1], points[index]))
        }
    }

    private static func polygonAreaM2(
        _ points: [OfflineMapPointE6],
        around origin: OfflineMapPointE6
    ) -> Double {
        guard points.count >= 3 else { return 0 }
        var twiceArea = 0.0
        for index in points.indices {
            let (x1, y1) = localMetres(points[index], around: origin)
            let (x2, y2) = localMetres(points[(index + 1) % points.count], around: origin)
            twiceArea += x1 * y2 - x2 * y1
        }
        return abs(twiceArea) / 2
    }

    private static func pointInPolygon(
        _ point: OfflineMapPointE6,
        _ polygon: [OfflineMapPointE6]
    ) -> Bool {
        var inside = false
        var previous = polygon.last!
        for current in polygon {
            let crosses = (current.latitudeE6 > point.latitudeE6) !=
                (previous.latitudeE6 > point.latitudeE6)
            if crosses {
                let longitude = Double(previous.longitudeE6 - current.longitudeE6) *
                    Double(point.latitudeE6 - current.latitudeE6) /
                    Double(previous.latitudeE6 - current.latitudeE6) +
                    Double(current.longitudeE6)
                if Double(point.longitudeE6) < longitude { inside.toggle() }
            }
            previous = current
        }
        return inside
    }

    private static func segmentDistanceM(
        _ point: OfflineMapPointE6,
        _ start: OfflineMapPointE6,
        _ end: OfflineMapPointE6
    ) -> Double {
        let (px, py) = localMetres(point, around: point)
        let (ax, ay) = localMetres(start, around: point)
        let (bx, by) = localMetres(end, around: point)
        let dx = bx - ax
        let dy = by - ay
        let denominator = dx * dx + dy * dy
        let ratio = denominator == 0 ? 0 :
            max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / denominator))
        return hypot(px - (ax + ratio * dx), py - (ay + ratio * dy))
    }

    private static func distanceM(
        _ lhs: OfflineMapPointE6,
        _ rhs: OfflineMapPointE6
    ) -> Double {
        let (x, y) = localMetres(lhs, around: rhs)
        return hypot(x, y)
    }

    private static func localMetres(
        _ point: OfflineMapPointE6,
        around origin: OfflineMapPointE6
    ) -> (Double, Double) {
        let metresPerLatitudeE6 = 111_195.0 / 1_000_000
        let latitudeRadians = Double(origin.latitudeE6) / 1_000_000 * .pi / 180
        let metresPerLongitudeE6 = metresPerLatitudeE6 * cos(latitudeRadians)
        return (
            Double(point.longitudeE6 - origin.longitudeE6) * metresPerLongitudeE6,
            Double(point.latitudeE6 - origin.latitudeE6) * metresPerLatitudeE6
        )
    }
}
extension OfflineMapSceneWindow {
    var encodedPayloadByteCount: Int {
        18 + roads.reduce(0) { $0 + featureBytes($1.points) } +
            buildings.reduce(0) { $0 + featureBytes($1.points) }
    }

    /// Select complete features within the negotiated radio/memory budget.
    /// Alternate roads and footprints so a low-MTU link retains both context
    /// layers. Never truncate a footprint or reorder its boundary vertices.
    func forTransmission(denseBuildings: Bool, payloadBudget: Int) -> Self {
        let maximumBuildings = denseBuildings ? 48 : 16
        let maximumBuildingPoints = denseBuildings ? 240 : 128
        var selectedRoads: [OfflineMapRoad] = []
        var selectedBuildings: [OfflineMapBuilding] = []
        var bytes = 18, roadPoints = 0, buildingPoints = 0
        var roadIndex = 0, buildingIndex = 0
        while roadIndex < roads.count || buildingIndex < buildings.count {
            if roadIndex < roads.count {
                let road = roads[roadIndex]
                roadIndex += 1
                let cost = featureBytes(road.points)
                if selectedRoads.count < 24 && roadPoints + road.points.count <= 192 &&
                    bytes + cost <= payloadBudget {
                    selectedRoads.append(road)
                    roadPoints += road.points.count
                    bytes += cost
                }
            }
            for _ in 0..<2 where buildingIndex < buildings.count {
                let building = buildings[buildingIndex]
                buildingIndex += 1
                let cost = featureBytes(building.points)
                if selectedBuildings.count < maximumBuildings &&
                    buildingPoints + building.points.count <= maximumBuildingPoints &&
                    bytes + cost <= payloadBudget {
                    selectedBuildings.append(building)
                    buildingPoints += building.points.count
                    bytes += cost
                }
            }
        }
        return Self(revision: revision, origin: origin, radiusM: radiusM,
                    roads: selectedRoads, buildings: selectedBuildings)
    }

    private func featureBytes(_ points: [OfflineMapPointE6]) -> Int {
        2 + points.reduce(0) {
            $0 + Self.signedVarintBytes(Int64($1.latitudeE6) - Int64(origin.latitudeE6)) +
                Self.signedVarintBytes(Int64($1.longitudeE6) - Int64(origin.longitudeE6))
        }
    }

    private static func signedVarintBytes(_ value: Int64) -> Int {
        var encoded = UInt64(bitPattern: (value << 1) ^ (value >> 63))
        var bytes = 1
        while encoded >= 128 { encoded >>= 7; bytes += 1 }
        return bytes
    }
}

