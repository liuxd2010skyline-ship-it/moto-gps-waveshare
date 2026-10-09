import Foundation
import XCTest
@testable import MotoMapGeometry

final class OfflineGeometryTests: XCTestCase {
    private let origin = OfflineMapPointE6(latitudeE6: 39_984_500, longitudeE6: 116_322_500)

    func testLongRoadIsCutAtActualCircleIntersections() {
        let road = OfflineMapRoad(osmWayID: 1, roadClass: "primary",
            points: [point(-20_000, 0), point(20_000, 0)])
        let scene = window(roads: [road])
        XCTAssertEqual(scene.roads.count, 1)
        XCTAssertEqual(scene.roads[0].points.count, 2)
        for point in scene.roads[0].points {
            XCTAssertEqual(distance(point), 500, accuracy: 0.2)
            XCTAssertLessThan(abs(Int64(point.latitudeE6) - Int64(origin.latitudeE6)), 100_000)
        }
    }

    func testOutsideExcursionDoesNotCreateAFalseCrossMapRoad() {
        let road = OfflineMapRoad(osmWayID: 2, roadClass: "service", points: [
            point(0, 0), point(700, 0), point(700, 700), point(0, 200)])
        let scene = window(roads: [road])
        XCTAssertEqual(scene.roads.count, 2)
        XCTAssertNotEqual(scene.roads[0].points.last, scene.roads[1].points.first)
    }

    func testReversedRoadAndRotatedClosedFootprintDeduplicate() {
        let road = OfflineMapRoad(osmWayID: 3, roadClass: "residential", points: [point(-10, 0), point(10, 0)])
        let ring = [point(30, 30), point(30, 50), point(50, 50), point(50, 30)]
        let reversed = Array((ring.dropFirst() + [ring[0]]).reversed())
        let scene = window(roads: [road, OfflineMapRoad(osmWayID: 4, roadClass: "residential", points: Array(road.points.reversed()))],
            buildings: [building(1, ring), building(2, reversed + [reversed[0]])])
        XCTAssertEqual(scene.roads.count, 1)
        XCTAssertEqual(scene.buildings.count, 1)
        XCTAssertEqual(scene.buildings[0].points.count, 4)
    }

    func testDenseWindowKeepsFortyEightCompleteRealBoundariesWithinBudgets() {
        let buildings = (0..<60).map { i in
            let x = Double(i % 10) * 30, y = Double(i / 10) * 30
            return building(Int64(i), [point(x, y), point(x+12, y), point(x+16, y+8),
                                      point(x+12, y+16), point(x, y+16)])
        }
        let scene = window(buildings: buildings)
        XCTAssertEqual(scene.buildings.count, 48)
        XCTAssertEqual(scene.buildings.reduce(0) { $0 + $1.points.count }, 240)
        XCTAssertTrue(scene.buildings.allSatisfy { $0.points.count == 5 })
        let legacy = scene.forTransmission(denseBuildings: false, payloadBudget: 4096)
        XCTAssertEqual(legacy.buildings.count, 16)
        XCTAssertLessThanOrEqual(legacy.buildings.reduce(0) { $0 + $1.points.count }, 128)
    }

    func testTinyMtuRetainsBothLayersWithoutCuttingAnyFootprint() {
        let roads = (0..<24).map { i in OfflineMapRoad(osmWayID: Int64(i), roadClass: "primary",
            points: [point(Double(i)*10, -400), point(Double(i)*10, 400)]) }
        let buildings = (0..<48).map { i in
            let x = Double(i % 8)*30, y = Double(i / 8)*30
            return building(Int64(i), [point(x,y),point(x+12,y),point(x+12,y+12),point(x,y+12)])
        }
        let scene = window(roads: roads, buildings: buildings)
            .forTransmission(denseBuildings: true, payloadBudget: 768)
        XCTAssertFalse(scene.roads.isEmpty)
        XCTAssertFalse(scene.buildings.isEmpty)
        XCTAssertLessThanOrEqual(scene.encodedPayloadByteCount, 768)
        XCTAssertTrue(scene.buildings.allSatisfy { $0.points.count == 4 })
    }

    func testJinanPackCannotAppearUnderAHaidianRoute() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../").standardizedFileURL
        let index = try SQLiteOfflineMapSceneIndex(url: root.appendingPathComponent("shared/offline_map/jinan-v1.sqlite"))
        let region = OfflineMapRegionIndex(indexes: [index])
        let empty = region.query(around: origin, radiusM: 500, revision: 10)
        XCTAssertTrue(empty.roads.isEmpty)
        XCTAssertTrue(empty.buildings.isEmpty)
        XCTAssertEqual(empty.origin, origin)
        let jinan = region.query(around: OfflineMapPointE6(latitudeE6:36_632_524,longitudeE6:116_949_089),
                                 radiusM:500,revision:11)
        XCTAssertFalse(jinan.roads.isEmpty)
        XCTAssertFalse(jinan.buildings.isEmpty)
    }

    func testVerifiedBeijingPackProvidesRealHaidianGeometry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../").standardizedFileURL
        let url = root.appendingPathComponent("build/offline-maps/beijing-v1.sqlite")
        if !FileManager.default.fileExists(atPath: url.path) {
            if ProcessInfo.processInfo.environment["MOTO_REQUIRE_BEIJING_MAP"] == "1" {
                XCTFail("Beijing offline resource was not built")
                return
            }
            throw XCTSkip("Run prepare_beijing_pack.py to verify actual Beijing data")
        }
        let index = try SQLiteOfflineMapSceneIndex(url: url)
        let scene = index.query(around: origin, radiusM:500,revision:1)
        XCTAssertFalse(scene.roads.isEmpty)
        XCTAssertFalse(scene.buildings.isEmpty)
        XCTAssertTrue(scene.buildings.allSatisfy { $0.osmWayID != nil })
        XCTAssertLessThanOrEqual(scene.buildings.count, 48)
        XCTAssertLessThanOrEqual(scene.encodedPayloadByteCount, 4096)
        print("Haidian round-screen window: \(scene.roads.count) roads, \(scene.buildings.count) buildings, \(scene.encodedPayloadByteCount) bytes")
    }

    private func window(roads: [OfflineMapRoad] = [], buildings: [OfflineMapBuilding] = []) -> OfflineMapSceneWindow {
        let document = OfflineMapSceneDocument(schemaVersion:1,coordinateSystem:"GCJ-02",
            sceneRevision:1,viewOrigin:origin,radiusM:500,roads:roads,buildings:buildings,
            source:OfflineMapSource(provider:"geometry-test",licence:"test",attributionURL:"",retrievedAt:"",bboxWGS84:nil))
        return InMemoryOfflineMapSceneIndex(document:document).query(around:origin,radiusM:500,revision:1)
    }
    private func building(_ id: Int64, _ points: [OfflineMapPointE6]) -> OfflineMapBuilding {
        OfflineMapBuilding(osmWayID:id,name:nil,buildingClass:"generic",points:points)
    }
    private func point(_ northM: Double, _ eastM: Double) -> OfflineMapPointE6 {
        OfflineMapPointE6(latitudeE6:origin.latitudeE6 + Int32((northM/0.111195).rounded()),
                         longitudeE6:origin.longitudeE6 + Int32((eastM/(0.111195*cos(39.9845 * .pi/180))).rounded()))
    }
    private func distance(_ point: OfflineMapPointE6) -> Double {
        hypot(Double(point.latitudeE6-origin.latitudeE6)*0.111195,
              Double(point.longitudeE6-origin.longitudeE6)*0.111195*cos(39.9845 * .pi/180))
    }
}
