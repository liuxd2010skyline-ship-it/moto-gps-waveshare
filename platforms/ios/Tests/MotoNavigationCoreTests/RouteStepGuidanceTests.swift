import XCTest
@testable import MotoNavigationCore

final class RouteStepGuidanceTests: XCTestCase {
    // 111m north, then 111m east: a real right turn at vertex 1.
    let right: [GCJ02Point] = [
        .init(longitudeDeg: 0, latitudeDeg: 0),
        .init(longitudeDeg: 0, latitudeDeg: 0.001),
        .init(longitudeDeg: 0.001, latitudeDeg: 0.001)
    ]

    func testExitInstructionIsAttachedToJunctionNotStepStart() {
        let result = RouteStepGuidance.maneuvers(points: right, steps: [
            .init(startIndex: 0, endIndex: 1, instruction: "沿道路骑行100米，右转", road: "甲路"),
            .init(startIndex: 1, endIndex: 2, instruction: "沿乙路骑行100米", road: "乙路")
        ], totalDistanceM: 200)
        XCTAssertEqual(result.map(\.type), [.right, .arrive])
        XCTAssertEqual(result[0].routeOffsetM, 100, accuracy: 0.1)
    }

    func testEntranceInstructionDeduplicatesSameJunction() {
        let result = RouteStepGuidance.maneuvers(points: right, steps: [
            .init(startIndex: 0, endIndex: 1, instruction: "骑行100米右转", road: "甲路"),
            .init(startIndex: 1, endIndex: 2, instruction: "右转，沿乙路骑行100米", road: "乙路")
        ], totalDistanceM: 200)
        XCTAssertEqual(result.map(\.type), [.right, .arrive])
        XCTAssertEqual(result[0].routeOffsetM, 100, accuracy: 0.1)
    }

    func testMissingTurnWordsUseRealStepBoundary() {
        let result = RouteStepGuidance.maneuvers(points: right, steps: [
            .init(startIndex: 0, endIndex: 1, instruction: "直行100米", road: "甲路"),
            .init(startIndex: 1, endIndex: 2, instruction: "继续行驶", road: "乙路")
        ], totalDistanceM: 260)
        XCTAssertEqual(result.first?.type, .right)
        // The shared matcher scales geometry to the same full-route distance.
        XCTAssertEqual(result[0].routeOffsetM, 130, accuracy: 0.1)
    }

    func testHTMLAndTurnSynonyms() {
        let result = RouteStepGuidance.maneuvers(points: right, steps: [
            .init(startIndex: 0, endIndex: 1, instruction: "骑行<b>100</b>米，右<b>拐</b>", road: "甲路")
        ], totalDistanceM: 200)
        XCTAssertEqual(result.first?.type, .right)
        XCTAssertEqual(result[0].routeOffsetM, 100, accuracy: 0.1)
        XCTAssertEqual(RouteStepGuidance.plainInstruction("右<b>转</b>&nbsp;进入"), "右转 进入")
    }

    func testLeftAndConsecutiveTurnsRemainDistinct() {
        let points = right + [.init(longitudeDeg: 0.001, latitudeDeg: 0.002)]
        let result = RouteStepGuidance.maneuvers(points: points, steps: [
            .init(startIndex: 0, endIndex: 1, instruction: "直行", road: "甲路"),
            .init(startIndex: 1, endIndex: 2, instruction: "骑行100米左转", road: "乙路"),
            .init(startIndex: 2, endIndex: 3, instruction: "直行", road: "丙路")
        ], totalDistanceM: 300)
        XCTAssertEqual(result.map(\.type), [.right, .left, .arrive])
        XCTAssertEqual(result[0].routeOffsetM, 100, accuracy: 0.1)
        XCTAssertEqual(result[1].routeOffsetM, 200, accuracy: 0.1)
    }

    func testDoNotManufactureInstructionAtUnlabelledInteriorRoadCurve() {
        let result = RouteStepGuidance.maneuvers(points: right, steps: [
            .init(startIndex: 0, endIndex: 2, instruction: "沿道路继续行驶", road: "弯道")
        ], totalDistanceM: 200)
        XCTAssertEqual(result.map(\.type), [.arrive])
    }

    func testMalformedStepIndicesAreIgnored() {
        let result = RouteStepGuidance.maneuvers(points: right, steps: [
            .init(startIndex: -1, endIndex: 1, instruction: "右转", road: ""),
            .init(startIndex: 0, endIndex: 99, instruction: "左转", road: "")
        ], totalDistanceM: 200)
        XCTAssertEqual(result.map(\.type), [.arrive])
        XCTAssertTrue(RouteStepGuidance.maneuvers(points: right, steps: [], totalDistanceM: .nan).isEmpty)
    }
}
