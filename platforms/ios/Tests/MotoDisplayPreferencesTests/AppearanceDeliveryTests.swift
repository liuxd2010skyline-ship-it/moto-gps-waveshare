import XCTest
@testable import MotoDisplayPreferences

final class AppearanceDeliveryTests: XCTestCase {
    func testRetriesAreBoundedAndOldEchoCannotConfirmNewValue() {
        var delivery = RoundScreenAppearanceDelivery()
        let oldRevision = delivery.revision
        delivery.sent(nowMs: 1_000)
        XCTAssertFalse(delivery.shouldSend(nowMs: 2_999))
        XCTAssertTrue(delivery.shouldSend(nowMs: 3_000))
        delivery.sent(nowMs: 3_000)
        delivery.sent(nowMs: 5_000)
        XCTAssertFalse(delivery.shouldSend(nowMs: 8_000))
        var value = RoundScreenAppearance(); value.intensity = 80
        delivery.stage(value)
        XCTAssertTrue(delivery.shouldSend(nowMs: 8_000))
        XCTAssertFalse(delivery.acceptEcho(revision: oldRevision, value: RoundScreenAppearance()))
        XCTAssertFalse(delivery.acceptEcho(revision: delivery.revision, value: RoundScreenAppearance()))
        XCTAssertTrue(delivery.acceptEcho(revision: delivery.revision, value: value))
        XCTAssertFalse(delivery.shouldSend(nowMs: 10_000))
        delivery.resetSession()
        XCTAssertTrue(delivery.shouldSend(nowMs: 10_000))
        XCTAssertEqual(delivery.value, value)
    }
    func testBoundsAndBrightnessPreservation() {
        var value = RoundScreenAppearance()
        XCTAssertEqual(value.brightness, 0)
        value.intensity = 1_000; value.speed = -10; value.travel = 200; value.brightness = 1
        XCTAssertEqual(value.bounded.intensity, 100)
        XCTAssertEqual(value.bounded.speed, 0)
        XCTAssertEqual(value.bounded.travel, 100)
        XCTAssertEqual(value.bounded.brightness, 10)
        value.brightness = 0
        XCTAssertEqual(value.bounded.brightness, 0)
    }
}
