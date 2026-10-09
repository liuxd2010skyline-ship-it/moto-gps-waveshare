import Foundation

@MainActor
final class OfflineMapSceneCoordinator {
    private let index: any OfflineMapSceneQuerying
    private let radiusM: UInt16
    private let refreshDistanceM: Double
    private var lastOrigin: OfflineMapPointE6?
    private var revision: UInt32 = 0

    init(index: any OfflineMapSceneQuerying, radiusM: UInt16 = 500, refreshDistanceM: Double = 100) {
        self.index = index
        self.radiusM = max(500, min(800, radiusM))
        self.refreshDistanceM = max(25, refreshDistanceM)
    }

    convenience init(bundle: Bundle = .main) throws {
        let databaseName = "jinan-v1"
        var databaseURLs: [URL] = []
        if let supportRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let downloadedURL = supportRoot
                .appendingPathComponent("OfflineMaps", isDirectory: true)
                .appendingPathComponent("\(databaseName).sqlite")
            databaseURLs.append(downloadedURL)
        }
        if let bundledDatabase = bundle.url(forResource: databaseName, withExtension: "sqlite") {
            databaseURLs.append(bundledDatabase)
        }
        self.init(index: try Self.loadIndex(databaseURLs: databaseURLs, sampleURL: bundle.url(
            forResource: "jinan_map_scene_sample",
            withExtension: "json"
        )))
    }

    static func loadIndex(databaseURLs: [URL], sampleURL: URL?) throws -> any OfflineMapSceneQuerying {
        for url in databaseURLs where FileManager.default.fileExists(atPath: url.path) {
            do {
                let index = try SQLiteOfflineMapSceneIndex(url: url)
                #if DEBUG
                print("[MotoMap] loaded \(url.lastPathComponent)")
                #endif
                return index
            } catch {
                // An incomplete downloaded pack must not disable the intact
                // city map shipped with the app.
                #if DEBUG
                print("[MotoMap] invalid map \(url.lastPathComponent): \(error)")
                #endif
            }
        }
        guard let url = sampleURL else { throw OfflineMapSceneError.resourceMissing }
        let document = try OfflineMapSceneDocument.decode(Data(contentsOf: url))
        return InMemoryOfflineMapSceneIndex(document: document)
    }

    func sceneIfNeeded(latitudeDeg: Double, longitudeDeg: Double) -> OfflineMapSceneWindow? {
        guard latitudeDeg.isFinite, longitudeDeg.isFinite else { return nil }
        let origin = OfflineMapPointE6(
            latitudeE6: Int32(clamping: Int64((latitudeDeg * 1_000_000).rounded())),
            longitudeE6: Int32(clamping: Int64((longitudeDeg * 1_000_000).rounded()))
        )
        if let lastOrigin,
           Self.distanceM(lastOrigin, origin) < refreshDistanceM {
            return nil
        }
        revision &+= 1
        if revision == 0 { revision = 1 }
        lastOrigin = origin
        return index.query(around: origin, radiusM: radiusM, revision: revision)
    }

    func reset() {
        lastOrigin = nil
    }

    private static func distanceM(_ lhs: OfflineMapPointE6, _ rhs: OfflineMapPointE6) -> Double {
        let latitudeRadians = Double(rhs.latitudeE6) / 1_000_000 * .pi / 180
        let northM = Double(lhs.latitudeE6 - rhs.latitudeE6) * 111_195 / 1_000_000
        let eastM = Double(lhs.longitudeE6 - rhs.longitudeE6) *
            111_195 * cos(latitudeRadians) / 1_000_000
        return hypot(eastM, northM)
    }
}

extension OfflineMapSceneWindow {
    func makeBLEInput() -> MotoBLEMapSceneInput {
        let input = MotoBLEMapSceneInput()
        input.sceneRevision = revision
        input.originLatitudeE6 = origin.latitudeE6
        input.originLongitudeE6 = origin.longitudeE6
        input.radiusM = radiusM
        input.roads = roads.map { road in
            let value = MotoBLEMapRoadInput()
            value.className = road.roadClass
            value.points = road.points.map { point in
                let value = MotoBLEMapPointInput()
                value.latitudeE6 = point.latitudeE6
                value.longitudeE6 = point.longitudeE6
                return value
            }
            return value
        }
        input.buildings = buildings.map { building in
            let value = MotoBLEMapBuildingInput()
            value.className = building.buildingClass
            value.points = building.points.map { point in
                let value = MotoBLEMapPointInput()
                value.latitudeE6 = point.latitudeE6
                value.longitudeE6 = point.longitudeE6
                return value
            }
            return value
        }
        return input
    }
}
