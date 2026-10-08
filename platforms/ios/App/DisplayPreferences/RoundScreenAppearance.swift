import Foundation

struct RoundScreenAppearance: Codable, Equatable {
    var intensity = 62
    var speed = 75
    var travel = 85
    var reduceMotion = false
    // Zero preserves the brightness set with the physical device button.
    var brightness = 0

    var bounded: Self {
        var result = self
        result.intensity = min(100, max(0, intensity))
        result.speed = min(100, max(0, speed))
        result.travel = min(100, max(0, travel))
        result.brightness = brightness == 0 ? 0 : min(100, max(10, brightness))
        return result
    }

    private static let key = "MotoGPS.RoundScreenAppearance.v1"
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return value.bounded
    }
    func save() {
        if let data = try? JSONEncoder().encode(bounded) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// Transport acceptance is distinct from the device's render-thread echo.
// Older echoes cannot confirm a new slider position. Three attempts per value,
// with a two-second deadline, avoid flooding an already busy navigation link.
struct RoundScreenAppearanceDelivery {
    private(set) var value = RoundScreenAppearance()
    private(set) var revision: UInt32 = 1
    private(set) var attempts = 0
    private(set) var confirmed = false
    private var sentAtMs: UInt64?

    mutating func stage(_ next: RoundScreenAppearance) {
        guard next.bounded != value else { return }
        value = next.bounded
        revision = revision == .max ? 1 : revision + 1
        resetSession()
    }
    mutating func resetSession() {
        attempts = 0
        confirmed = false
        sentAtMs = nil
    }
    func shouldSend(nowMs: UInt64) -> Bool {
        guard !confirmed, attempts < 3 else { return false }
        guard let sentAtMs else { return true }
        return nowMs >= sentAtMs && nowMs - sentAtMs >= 2_000
    }
    mutating func sent(nowMs: UInt64) {
        sentAtMs = nowMs
        attempts += 1
    }
    mutating func acceptEcho(revision incoming: UInt32, value echoed: RoundScreenAppearance) -> Bool {
        guard incoming == revision, echoed == value else { return false }
        confirmed = true
        return true
    }
    var status: String {
        if confirmed { return "圆屏已应用" }
        if attempts >= 3 { return "尚未确认 · 可点击重试" }
        return attempts == 0 ? "等待同步" : "正在同步到圆屏"
    }
}
