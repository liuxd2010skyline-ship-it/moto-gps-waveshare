import MotoNavigationCore
import SwiftUI

/// Baidu's map view supplies real surrounding streets. A transparent UIKit
/// layer draws the selected Baidu route with the Waveshare renderer's shared
/// palette and stroke widths, so a route can be checked against those streets.
struct RouteOverviewMap: View {
    let candidates: [RoutePreviewCandidate]
    let selectedID: String?
    @AppStorage(BaiduMapSetup.mapStyleIDKey) private var mapStyleID = ""

    private var selectedRoute: RoutePlan? {
        candidates.first(where: { $0.id == selectedID })?.route
            ?? candidates.first?.route
    }

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            ZStack {
                Color(red: 5.0 / 255, green: 6.0 / 255, blue: 7.0 / 255)
                BaiduRoutePreviewSurface(points: selectedRoute?.polyline ?? [],
                                         mapStyleID: mapStyleID)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                Circle()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                    .allowsHitTesting(false)
                HStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    Text("百度路线预览")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.78), in: Capsule())
                .offset(y: -diameter / 2 + 31)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 5.0 / 255, green: 6.0 / 255, blue: 7.0 / 255))
    }
}

private struct BaiduRoutePreviewSurface: UIViewRepresentable {
    let points: [GCJ02Point]
    let mapStyleID: String

    func makeUIView(context: Context) -> BaiduRoutePreviewView {
        BaiduRoutePreviewView(frame: .zero)
    }

    func updateUIView(_ view: BaiduRoutePreviewView, context: Context) {
        view.useCustomMapStyleID(mapStyleID)
        view.showRoutePoints(points.map {
            ["latitude": NSNumber(value: $0.latitudeDeg),
             "longitude": NSNumber(value: $0.longitudeDeg)]
        })
    }
}
