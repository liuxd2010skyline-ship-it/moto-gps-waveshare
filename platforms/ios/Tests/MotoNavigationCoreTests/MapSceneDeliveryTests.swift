import XCTest
@testable import MotoNavigationCore

final class MapSceneDeliveryTests: XCTestCase {
    func testTimeoutStartsAtLastFragmentAndIgnoresStaleAcknowledgement() {
        var delivery = BLEMapSceneDelivery()
        delivery.queued(revision: 1, sequence: 7)
        delivery.expire(nowMs: 90_000)
        XCTAssertEqual(delivery.timeoutCount, 0)
        XCTAssertTrue(delivery.isWritingFragments)
        XCTAssertFalse(delivery.acknowledge(sequence: 6, status: 0))
        delivery.lastFragmentWritten(nowMs: 90_000)
        delivery.expire(nowMs: 92_999)
        XCTAssertEqual(delivery.timeoutCount, 0)
        delivery.expire(nowMs: 93_000)
        XCTAssertEqual(delivery.timeoutCount, 1)
        XCTAssertTrue(delivery.shouldSend(revision: 1, queuedFrames: 0))
    }

    func testFailedRevisionCannotPoisonTheNextGeographicWindow() {
        var delivery = BLEMapSceneDelivery()
        for sequence in UInt16(1)...3 {
            delivery.sent(revision: 10, sequence: sequence, nowMs: 0)
            XCTAssertTrue(delivery.acknowledge(sequence: sequence, status: 3))
        }
        XCTAssertFalse(delivery.shouldSend(revision: 10, queuedFrames: 0))
        XCTAssertTrue(delivery.shouldSend(revision: 11, queuedFrames: 0))
        delivery.queued(revision: 11, sequence: 4)
        XCTAssertEqual(delivery.timeoutCount, 0)
        XCTAssertFalse(delivery.acknowledge(sequence: 3, status: 0))
        delivery.lastFragmentWritten(nowMs: 1_000)
        XCTAssertTrue(delivery.acknowledge(sequence: 4, status: 4))
        XCTAssertEqual(delivery.acknowledgedRevision, 11)
        XCTAssertFalse(delivery.shouldSend(revision: 11, queuedFrames: 0))
    }

    func testBulkStartsOnlyAfterOlderLogicalMessagesDrain() {
        let delivery = BLEMapSceneDelivery()
        XCTAssertFalse(delivery.shouldSend(revision: 1, queuedFrames: 1))
        XCTAssertTrue(delivery.shouldSend(revision: 1, queuedFrames: 0))
        XCTAssertEqual(BLEMapTransferBudget.payloadBytes(maximumFrameSize: 20), 768)
        XCTAssertEqual(BLEMapTransferBudget.payloadBytes(maximumFrameSize: 182), 4096)
    }
}
