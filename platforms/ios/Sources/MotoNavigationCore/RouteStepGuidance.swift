import Foundation

/// A provider step is a road segment, not necessarily a turn at its START.
/// Vertex indices retain the SDK's real geometry and avoid mixing its rounded
/// step distances with NavCore's geometry-scaled route-progress baseline.
public struct RouteGuidanceStep: Sendable {
    public let startIndex: Int
    public let endIndex: Int
    public let instruction: String
    public let road: String

    public init(startIndex: Int, endIndex: Int, instruction: String, road: String) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.instruction = instruction
        self.road = road
    }
}

public enum RouteStepGuidance {
    public static func maneuvers(points: [GCJ02Point], steps: [RouteGuidanceStep],
                                 totalDistanceM: Double) -> [RouteManeuver] {
        guard points.count >= 2, totalDistanceM.isFinite, totalDistanceM > 0 else { return [] }
        var distances = [Double](repeating: 0, count: points.count)
        for i in 1..<points.count { distances[i] = distances[i - 1] + distance(points[i - 1], points[i]) }
        guard let length = distances.last, length > 0 else { return [] }
        let scale = totalDistanceM / length
        struct Candidate {
            var index: Int
            var type: ManeuverType
            var road: String
            var explicit: Bool
        }
        var candidates: [Candidate] = []
        func turn(at index: Int) -> Double? {
            guard index > 0, index < points.count - 1 else { return nil }
            var before = index - 1, after = index + 1
            while before > 0 && distances[index] - distances[before] < 8 { before -= 1 }
            while after < points.count - 1 && distances[after] - distances[index] < 8 { after += 1 }
            guard distances[index] - distances[before] >= 2,
                  distances[after] - distances[index] >= 2 else { return nil }
            return delta(bearing(points[index], points[after]) - bearing(points[before], points[index]))
        }
        for step in steps {
            guard step.startIndex >= 0, step.endIndex >= step.startIndex,
                  step.endIndex < points.count else { continue }
            let text = plainInstruction(step.instruction)
            if let action = action(in: text) {
                // "ride 300 m, turn right" belongs at the exit; "turn right,
                // ride 300 m" belongs at the entrance. The old converter
                // attached BOTH to the entrance and consumed turns early.
                let prefix = String(text[..<action.range.lowerBound])
                let followsDistance = prefix.range(of: #"\d+(?:\.\d+)?\s*(?:米|公里|m\b|km\b)"#,
                                                   options: [.regularExpression, .caseInsensitive]) != nil
                let preferred = followsDistance ? step.endIndex : step.startIndex
                var selected = preferred
                if isDirectional(action.type) {
                    // Find the corresponding real bend in this step. This
                    // also handles a provider boundary slightly past a corner.
                    let matches = (step.startIndex...step.endIndex).filter { i in
                        guard let angle = turn(at: i) else { return false }
                        return agrees(action.type, angle: angle)
                    }
                    if let nearest = matches.min(by: {
                        abs(distances[$0] - distances[preferred]) < abs(distances[$1] - distances[preferred])
                    }) { selected = nearest }
                }
                if selected > 0 && selected < points.count - 1 {
                    candidates.append(Candidate(index: selected, type: action.type,
                                                road: step.road, explicit: true))
                }
            }
            // Supplement missing words only at SDK step boundaries. Do not
            // manufacture turn instructions at every curve in a road.
            for index in [step.startIndex, step.endIndex] {
                if let angle = turn(at: index), abs(angle) >= 35 {
                    candidates.append(Candidate(index: index, type: type(for: angle),
                                                road: step.road, explicit: false))
                }
            }
        }
        candidates.sort {
            if $0.index != $1.index { return $0.index < $1.index }
            return $0.explicit && !$1.explicit
        }
        var accepted: [Candidate] = []
        for candidate in candidates {
            if let last = accepted.last,
               abs(distances[last.index] - distances[candidate.index]) <= 6 {
                if candidate.explicit && !last.explicit { accepted[accepted.count - 1] = candidate }
            } else { accepted.append(candidate) }
        }
        let turns = accepted.enumerated().map { index, value in
            RouteManeuver(id: UInt32(index + 1), type: value.type,
                          routeOffsetM: distances[value.index] * scale,
                          roadName: value.road, instruction: instruction(for: value.type))
        }
        return turns + [RouteManeuver(id: UInt32(turns.count + 1), type: .arrive,
                                     routeOffsetM: totalDistanceM, roadName: "目的地", instruction: "到达目的地")]
    }

    public static func plainInstruction(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func action(in text: String) -> (type: ManeuverType, range: Range<String.Index>)? {
        let groups: [(ManeuverType, String)] = [
            (.uTurnLeft, "掉头|调头|[Uu][- ]?turn"), (.roundabout, "进入环岛|进入环形|环岛"),
            (.sharpLeft, "向左后方|左后方|急左转"), (.sharpRight, "向右后方|右后方|急右转"),
            (.slightLeft, "靠左|左前方|左前|斜向左"), (.slightRight, "靠右|右前方|右前|斜向右"),
            (.left, "左转|左拐|向左(?:转|行驶)|turn left"),
            (.right, "右转|右拐|向右(?:转|行驶)|turn right"),
            (.exit, "驶出|离开环岛")
        ]
        // Prioritize the first action in the sentence, using a more specific
        // match at the same position. HTML can otherwise split "右<..>转".
        var result: (type: ManeuverType, range: Range<String.Index>)?
        for (type, pattern) in groups {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
               result == nil || range.lowerBound < result!.range.lowerBound {
                result = (type, range)
            }
        }
        return result
    }

    private static func isDirectional(_ type: ManeuverType) -> Bool {
        type != .roundabout && type != .exit
    }
    private static func agrees(_ type: ManeuverType, angle: Double) -> Bool {
        switch type {
        case .uTurnLeft, .uTurnRight: abs(angle) >= 150
        case .left, .sharpLeft, .slightLeft: angle <= -25 && angle > -165
        case .right, .sharpRight, .slightRight: angle >= 25 && angle < 165
        default: false
        }
    }
    private static func type(for angle: Double) -> ManeuverType {
        if abs(angle) >= 165 { return angle < 0 ? .uTurnLeft : .uTurnRight }
        if abs(angle) >= 135 { return angle < 0 ? .sharpLeft : .sharpRight }
        if abs(angle) < 55 { return angle < 0 ? .slightLeft : .slightRight }
        return angle < 0 ? .left : .right
    }
    private static func instruction(for type: ManeuverType) -> String {
        switch type {
        case .left: "前方左转"
        case .right: "前方右转"
        case .slightLeft: "前方偏左"
        case .slightRight: "前方偏右"
        case .sharpLeft: "前方急左转"
        case .sharpRight: "前方急右转"
        case .uTurnLeft, .uTurnRight: "前方掉头"
        case .roundabout: "进入环岛"
        case .exit: "前方驶出"
        default: "继续前行"
        }
    }
    private static func delta(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped > 180 ? wrapped - 360 : (wrapped < -180 ? wrapped + 360 : wrapped)
    }
    private static func bearing(_ a: GCJ02Point, _ b: GCJ02Point) -> Double {
        let east = delta(b.longitudeDeg - a.longitudeDeg) * cos((a.latitudeDeg + b.latitudeDeg) * .pi / 360)
        return atan2(east, b.latitudeDeg - a.latitudeDeg) * 180 / .pi
    }
    private static func distance(_ a: GCJ02Point, _ b: GCJ02Point) -> Double {
        let east = delta(b.longitudeDeg - a.longitudeDeg) * cos((a.latitudeDeg + b.latitudeDeg) * .pi / 360)
        return hypot(east, b.latitudeDeg - a.latitudeDeg) * .pi / 180 * 6_371_000
    }
}
