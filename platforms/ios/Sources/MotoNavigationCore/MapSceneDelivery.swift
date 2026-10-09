import Foundation

/// Delivery is acknowledged for a complete geographic window, not when
/// CoreBluetooth accepts its first fragment. Retry budgets belong to revisions.
public struct BLEMapSceneDelivery: Sendable {
    public private(set) var acknowledgedRevision: UInt32?
    public private(set) var pending: (revision: UInt32, sequence: UInt16, sentAtMs: UInt64?)?
    public private(set) var timeoutCount = 0
    private var attemptedRevision: UInt32?

    public init() {}

    public var isWritingFragments: Bool { pending != nil && pending?.sentAtMs == nil }

    public func shouldSend(revision: UInt32, queuedFrames: Int) -> Bool {
        pending == nil && acknowledgedRevision != revision && queuedFrames == 0 &&
            (attemptedRevision != revision || timeoutCount < 3)
    }

    private mutating func start(revision: UInt32, sequence: UInt16, sentAtMs: UInt64?) {
        if attemptedRevision != revision {
            attemptedRevision = revision
            timeoutCount = 0
        }
        pending = (revision, sequence, sentAtMs)
    }

    public mutating func sent(revision: UInt32, sequence: UInt16, nowMs: UInt64) {
        start(revision: revision, sequence: sequence, sentAtMs: nowMs)
    }

    public mutating func queued(revision: UInt32, sequence: UInt16) {
        start(revision: revision, sequence: sequence, sentAtMs: nil)
    }

    public mutating func lastFragmentWritten(nowMs: UInt64) {
        guard let pending else { return }
        self.pending = (pending.revision, pending.sequence, nowMs)
    }

    @discardableResult
    public mutating func acknowledge(sequence: UInt16, status: UInt8) -> Bool {
        guard let pending, pending.sequence == sequence else { return false }
        self.pending = nil
        if status == 0 || status == 4 {
            acknowledgedRevision = pending.revision
            timeoutCount = 0
        } else {
            timeoutCount += 1
        }
        return true
    }

    public mutating func expire(nowMs: UInt64) {
        guard let pending, let sentAt = pending.sentAtMs,
              nowMs >= sentAt, nowMs - sentAt >= 3_000 else { return }
        self.pending = nil
        timeoutCount += 1
    }

    public mutating func queueWasDiscarded() {
        pending = nil
        acknowledgedRevision = nil
    }
}

public enum BLEMapTransferBudget {
    // A 96-fragment map drains in about 1.44 s at the phone's 15 ms pacing,
    // below the terminal's 3.5 s link watchdog. No navigation batch can evict
    // a partially transmitted map. Backpressure can extend wall-clock time.
    public static let maximumFrames = 96
    public static func payloadBytes(maximumFrameSize: Int) -> Int {
        max(18, min(4_096, max(0, maximumFrameSize - 12) * maximumFrames))
    }
}
