import MotoNavigationCore
import SwiftUI

/// A route schematic drawn from Baidu's GCJ-02 geometry. It does not request
/// Apple map tiles or pretend to show nearby streets that are unavailable.
struct RouteOverviewMap: View {
    let candidates: [RoutePreviewCandidate]
    let selectedID: String?
    let origin: WGS84Point?
    let destination: WGS84Point

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: .secondarySystemGroupedBackground)
            Canvas { context, size in
                drawGrid(context: context, size: size)
                drawRoutes(context: context, size: size)
            }
            .padding(8)
            Label("路线示意 · 百度地图", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.caption.weight(.semibold))
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        var grid = Path()
        for x in stride(from: CGFloat(0), through: size.width, by: 32) {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: CGFloat(0), through: size.height, by: 32) {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(Color.primary.opacity(0.055)), lineWidth: 0.5)
    }

    private func drawRoutes(context: GraphicsContext, size: CGSize) {
        let allPoints = candidates.flatMap { $0.route.polyline }
        guard allPoints.count >= 2 else { return }
        let meanLatitude = allPoints.map(\.latitudeDeg).reduce(0, +) / Double(allPoints.count)
        let longitudeScale = max(0.1, cos(meanLatitude * .pi / 180))
        let xs = allPoints.map { $0.longitudeDeg * longitudeScale }
        let ys = allPoints.map(\.latitudeDeg)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max()
        else { return }
        let spanX = max(maxX - minX, 0.00001)
        let spanY = max(maxY - minY, 0.00001)
        let inset: CGFloat = 28
        let scale = min((size.width - inset * 2) / CGFloat(spanX),
                        (size.height - inset * 2) / CGFloat(spanY))
        let usedWidth = CGFloat(spanX) * scale
        let usedHeight = CGFloat(spanY) * scale
        let offsetX = (size.width - usedWidth) / 2
        let offsetY = (size.height - usedHeight) / 2

        func screenPoint(_ point: GCJ02Point) -> CGPoint {
            CGPoint(x: offsetX + CGFloat(point.longitudeDeg * longitudeScale - minX) * scale,
                    y: offsetY + CGFloat(maxY - point.latitudeDeg) * scale)
        }

        let ordered = candidates.sorted {
            ($0.id == selectedID ? 1 : 0) < ($1.id == selectedID ? 1 : 0)
        }
        for candidate in ordered {
            guard let first = candidate.route.polyline.first else { continue }
            var path = Path()
            path.move(to: screenPoint(first))
            for point in candidate.route.polyline.dropFirst() {
                path.addLine(to: screenPoint(point))
            }
            let selected = candidate.id == selectedID
            context.stroke(path, with: .color(selected ? .blue : .gray.opacity(0.55)),
                           style: StrokeStyle(lineWidth: selected ? 6 : 4,
                                              lineCap: .round, lineJoin: .round))
        }
        if let selected = candidates.first(where: { $0.id == selectedID }),
           let start = selected.route.polyline.first,
           let finish = selected.route.polyline.last {
            context.fill(Path(ellipseIn: CGRect(x: screenPoint(start).x - 7,
                                                 y: screenPoint(start).y - 7,
                                                 width: 14, height: 14)), with: .color(.blue))
            context.fill(Path(ellipseIn: CGRect(x: screenPoint(finish).x - 7,
                                                 y: screenPoint(finish).y - 7,
                                                 width: 14, height: 14)), with: .color(.red))
        }
    }
}
