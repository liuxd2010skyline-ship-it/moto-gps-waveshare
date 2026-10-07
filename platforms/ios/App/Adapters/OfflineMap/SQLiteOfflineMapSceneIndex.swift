import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

enum SQLiteOfflineMapError: Error, Equatable {
    case cannotOpen(Int32)
    case invalidSchema
    case prepareFailed(Int32)
}

/// Read-only repository for an MGPS v1 city pack.
///
/// R-tree only narrows candidates. The shared in-memory selector performs the
/// exact circular clip, visual-priority ordering and BLE capacity limits, so a
/// generated city pack and the bundled OSM fixture behave identically.
final class SQLiteOfflineMapSceneIndex: OfflineMapSceneQuerying, @unchecked Sendable {
    private let database: OpaquePointer
    private let lock = NSLock()
    private let coverage: (minimumLatitude: Int32, maximumLatitude: Int32,
                           minimumLongitude: Int32, maximumLongitude: Int32)

    init(url: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw SQLiteOfflineMapError.cannotOpen(result)
        }
        database = handle
        do {
            guard try Self.metadataValue("schema_version", database: handle) == "1",
                  try Self.metadataValue("coordinate_system", database: handle) == "GCJ-02",
                  sqlite3_user_version(handle) == 1,
                  try Self.scalarInt("PRAGMA application_id", database: handle) == 0x4d475053
            else { throw SQLiteOfflineMapError.invalidSchema }
            var statement: OpaquePointer?
            let sql = """
            SELECT min(min_lat_e6), max(max_lat_e6), min(min_lon_e6), max(max_lon_e6)
            FROM (SELECT min_lat_e6,max_lat_e6,min_lon_e6,max_lon_e6 FROM road_rtree
                  UNION ALL SELECT min_lat_e6,max_lat_e6,min_lon_e6,max_lon_e6 FROM building_rtree)
            """
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { throw SQLiteOfflineMapError.invalidSchema }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  sqlite3_column_type(statement, 0) != SQLITE_NULL else {
                throw SQLiteOfflineMapError.invalidSchema
            }
            coverage = (sqlite3_column_int(statement, 0), sqlite3_column_int(statement, 1),
                        sqlite3_column_int(statement, 2), sqlite3_column_int(statement, 3))
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func contains(_ origin: OfflineMapPointE6) -> Bool {
        (coverage.minimumLatitude...coverage.maximumLatitude).contains(origin.latitudeE6) &&
            (coverage.minimumLongitude...coverage.maximumLongitude).contains(origin.longitudeE6)
    }

    func query(
        around origin: OfflineMapPointE6,
        radiusM: UInt16,
        revision: UInt32
    ) -> OfflineMapSceneWindow {
        lock.lock()
        defer { lock.unlock() }

        let radius = UInt16(max(500, min(800, radiusM)))
        guard contains(origin) else {
            return OfflineMapSceneWindow(revision: revision, origin: origin, radiusM: radius,
                                         roads: [], buildings: [])
        }
        let bounds = Self.queryBounds(origin: origin, radiusM: Double(radius))
        do {
            let roads = try loadRoadCandidates(bounds: bounds, origin: origin)
            let buildings = try loadBuildingCandidates(bounds: bounds, origin: origin)
            let document = OfflineMapSceneDocument(
                schemaVersion: 1,
                coordinateSystem: "GCJ-02",
                sceneRevision: revision,
                viewOrigin: origin,
                radiusM: radius,
                roads: roads,
                buildings: buildings,
                source: OfflineMapSource(
                    provider: "offline-sqlite",
                    licence: "see metadata",
                    attributionURL: "",
                    retrievedAt: "",
                    bboxWGS84: nil
                )
            )
            return InMemoryOfflineMapSceneIndex(document: document).query(
                around: origin,
                radiusM: radius,
                revision: revision
            )
        } catch {
            // A damaged or concurrently replaced pack must never poison the
            // navigation stream. An empty, correctly revisioned scene clears
            // stale geometry on the device while the route itself continues.
            return OfflineMapSceneWindow(
                revision: revision,
                origin: origin,
                radiusM: radius,
                roads: [],
                buildings: []
            )
        }
    }

    private struct QueryBounds {
        let minimumLatitudeE6: Int32
        let maximumLatitudeE6: Int32
        let minimumLongitudeE6: Int32
        let maximumLongitudeE6: Int32
    }

    private func loadRoadCandidates(
        bounds: QueryBounds,
        origin: OfflineMapPointE6
    ) throws -> [OfflineMapRoad] {
        let sql = """
        SELECT r.osm_way_id, r.class, r.points
        FROM road_rtree AS x
        JOIN roads AS r ON r.id = x.id
        WHERE x.max_lat_e6 >= ?1 AND x.min_lat_e6 <= ?2
          AND x.max_lon_e6 >= ?3 AND x.min_lon_e6 <= ?4
        ORDER BY
          CASE r.class
            WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 0 THEN 2
            WHEN 3 THEN 3 WHEN 4 THEN 4 ELSE 5
          END,
          abs(((r.min_lat_e6 + r.max_lat_e6) / 2) - ?5) +
          abs(((r.min_lon_e6 + r.max_lon_e6) / 2) - ?6),
          r.id
        LIMIT 512
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        Self.bind(bounds, origin: origin, to: statement)

        var result: [OfflineMapRoad] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            defer { step = sqlite3_step(statement) }
            guard let points = Self.decodePoints(statement: statement, column: 2),
                  points.count >= 2
            else { continue }
            result.append(OfflineMapRoad(
                osmWayID: sqlite3_column_type(statement, 0) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(statement, 0),
                roadClass: Self.roadClass(sqlite3_column_int(statement, 1)),
                points: points
            ))
        }
        guard step == SQLITE_DONE else { throw SQLiteOfflineMapError.prepareFailed(step) }
        return result
    }

    private func loadBuildingCandidates(
        bounds: QueryBounds,
        origin: OfflineMapPointE6
    ) throws -> [OfflineMapBuilding] {
        let sql = """
        SELECT b.osm_way_id, b.name, b.class, b.points
        FROM building_rtree AS x
        JOIN buildings AS b ON b.id = x.id
        WHERE x.max_lat_e6 >= ?1 AND x.min_lat_e6 <= ?2
          AND x.max_lon_e6 >= ?3 AND x.min_lon_e6 <= ?4
        ORDER BY
          abs(((b.min_lat_e6 + b.max_lat_e6) / 2) - ?5) +
          abs(((b.min_lon_e6 + b.max_lon_e6) / 2) - ?6),
          ((b.max_lat_e6 - b.min_lat_e6) * (b.max_lon_e6 - b.min_lon_e6)) DESC,
          b.id
        LIMIT 512
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        Self.bind(bounds, origin: origin, to: statement)

        var result: [OfflineMapBuilding] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            defer { step = sqlite3_step(statement) }
            guard let points = Self.decodePoints(statement: statement, column: 3),
                  points.count >= 3,
                  points.first != points.last
            else { continue }
            let rawName = sqlite3_column_text(statement, 1)
            result.append(OfflineMapBuilding(
                osmWayID: sqlite3_column_type(statement, 0) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(statement, 0),
                name: rawName.map { String(cString: $0) },
                buildingClass: Self.buildingClass(sqlite3_column_int(statement, 2)),
                points: points
            ))
        }
        guard step == SQLITE_DONE else { throw SQLiteOfflineMapError.prepareFailed(step) }
        return result
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteOfflineMapError.prepareFailed(result)
        }
        return statement
    }

    private static func metadataValue(
        _ key: String,
        database: OpaquePointer
    ) throws -> String? {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(
            database,
            "SELECT value FROM metadata WHERE key = ?1",
            -1,
            &statement,
            nil
        )
        guard result == SQLITE_OK, let statement else {
            throw SQLiteOfflineMapError.prepareFailed(result)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0)
        else { return nil }
        return String(cString: value)
    }

    private static func scalarInt(_ sql: String, database: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw SQLiteOfflineMapError.invalidSchema }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw SQLiteOfflineMapError.invalidSchema }
        return sqlite3_column_int(statement, 0)
    }

    private static func bind(
        _ bounds: QueryBounds,
        origin: OfflineMapPointE6,
        to statement: OpaquePointer
    ) {
        sqlite3_bind_int(statement, 1, bounds.minimumLatitudeE6)
        sqlite3_bind_int(statement, 2, bounds.maximumLatitudeE6)
        sqlite3_bind_int(statement, 3, bounds.minimumLongitudeE6)
        sqlite3_bind_int(statement, 4, bounds.maximumLongitudeE6)
        sqlite3_bind_int(statement, 5, origin.latitudeE6)
        sqlite3_bind_int(statement, 6, origin.longitudeE6)
    }

    private static func queryBounds(
        origin: OfflineMapPointE6,
        radiusM: Double
    ) -> QueryBounds {
        let latitudeRadians = Double(origin.latitudeE6) / 1_000_000 * .pi / 180
        let latitudeDelta = Int32(ceil(radiusM / 111_195 * 1_000_000))
        let longitudeDelta = Int32(ceil(
            radiusM / max(1, 111_195 * cos(latitudeRadians)) * 1_000_000
        ))
        return QueryBounds(
            minimumLatitudeE6: origin.latitudeE6 &- latitudeDelta,
            maximumLatitudeE6: origin.latitudeE6 &+ latitudeDelta,
            minimumLongitudeE6: origin.longitudeE6 &- longitudeDelta,
            maximumLongitudeE6: origin.longitudeE6 &+ longitudeDelta
        )
    }

    private static func decodePoints(
        statement: OpaquePointer,
        column: Int32
    ) -> [OfflineMapPointE6]? {
        let byteCount = Int(sqlite3_column_bytes(statement, column))
        guard byteCount >= 8, byteCount <= 8 * 16_384, byteCount.isMultiple(of: 8),
              let raw = sqlite3_column_blob(statement, column)
        else { return nil }
        let bytes = raw.assumingMemoryBound(to: UInt8.self)
        var result: [OfflineMapPointE6] = []
        result.reserveCapacity(byteCount / 8)
        for offset in stride(from: 0, to: byteCount, by: 8) {
            result.append(OfflineMapPointE6(
                latitudeE6: decodeInt32LE(bytes + offset),
                longitudeE6: decodeInt32LE(bytes + offset + 4)
            ))
        }
        return result
    }

    private static func decodeInt32LE(_ bytes: UnsafePointer<UInt8>) -> Int32 {
        Int32(bitPattern:
            UInt32(bytes[0]) |
            UInt32(bytes[1]) << 8 |
            UInt32(bytes[2]) << 16 |
            UInt32(bytes[3]) << 24
        )
    }

    private static func roadClass(_ raw: Int32) -> String {
        switch raw {
        case 0: "motorway"
        case 1: "primary"
        case 2: "secondary"
        case 3: "residential"
        case 4: "service"
        default: "other"
        }
    }

    private static func buildingClass(_ raw: Int32) -> String {
        switch raw {
        case 1: "landmark"
        case 2: "parking"
        default: "generic"
        }
    }
}

struct OfflineMapRegionIndex: OfflineMapSceneQuerying {
    let indexes: [SQLiteOfflineMapSceneIndex]

    func query(around origin: OfflineMapPointE6, radiusM: UInt16,
               revision: UInt32) -> OfflineMapSceneWindow {
        // A region's extent selects the pack, not the current demo state.
        // Never translate a different city's geometry into the rider's window.
        guard let index = indexes.first(where: { $0.contains(origin) }) else {
            return OfflineMapSceneWindow(revision: revision, origin: origin, radiusM: radiusM,
                                         roads: [], buildings: [])
        }
        return index.query(around: origin, radiusM: radiusM, revision: revision)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func sqlite3_user_version(_ database: OpaquePointer) -> Int32 {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
          let statement
    else { return -1 }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
    return sqlite3_column_int(statement, 0)
}
