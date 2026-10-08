import SwiftUI

struct RoundScreenAppearanceView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        Form {
            Section {
                RoundScreenAppearancePreview(appearance: model.roundScreenAppearance,
                                             systemReduceMotion: systemReduceMotion)
                    .frame(width: 270, height: 270)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("圆屏外观示例：右转，三百米")
                Text("外观示例 · 实际道路与建筑随定位数据变化")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }.listRowBackground(Color.clear)
            Section {
                Toggle("静态柔光背景", isOn: $model.roundScreenAppearance.backgroundEnabled)
                if model.roundScreenAppearance.backgroundEnabled {
                    slider("存在感", value: $model.roundScreenAppearance.intensity, range: 1 ... 100)
                }
            } header: {
                Text("柔光")
            } footer: {
                Text("柔光只在设置改变时生成。关闭后进入基础模式，完全释放柔光图像；定位、道路、建筑、路线和操作继续正常更新。")
            }
            Section("屏幕亮度") {
                Toggle("保留圆屏本机亮度", isOn: Binding(
                    get: { model.roundScreenAppearance.brightness == 0 },
                    set: { model.roundScreenAppearance.brightness = $0 ? 0 : 60 }))
                if model.roundScreenAppearance.brightness != 0 {
                    slider("亮度", value: $model.roundScreenAppearance.brightness, range: 10 ... 100)
                }
            }
            Section {
                LabeledContent("状态", value: model.device.appearanceStatus)
                Button("重新同步", action: model.retryRoundScreenAppearance)
                Button("恢复设计默认值") { model.roundScreenAppearance = RoundScreenAppearance() }
            } header: {
                Text("同步")
            } footer: {
                Text("设置保存在手机和圆屏上。离线修改会在重新连接后自动同步。圆屏电量与本机亮度仍可通过短按电源键查看。")
            }
        }
        .navigationTitle("圆屏外观")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("round-screen-appearance")
    }

    private func slider(_ title: String, value: Binding<Int>, range: ClosedRange<Double> = 0 ... 100) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue)%").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0.rounded()) }),
                   in: range, step: 1)
        }
    }
}

// A labelled route-only appearance sample, never a substitute for Baidu's
// actual route preview. Native hardware captures are the implementation oracle.
private struct RoundScreenAppearancePreview: View {
    let appearance: RoundScreenAppearance
    let systemReduceMotion: Bool
    @State private var renderer = MotoAmbientPreview()
    private var frozen: Bool { true }
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: frozen)) { timeline in
            Canvas { context, size in
                let scale = size.width / 466
                context.scaleBy(x: scale, y: scale)
                let black = Color(red: 5 / 255, green: 7 / 255, blue: 8 / 255)
                context.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 466, height: 466)), with: .color(black))
                let milliseconds = UInt32(truncatingIfNeeded: Int64(timeline.date.timeIntervalSinceReferenceDate * 1000))
                let material = renderer.image(withIntensity: UInt8(appearance.bounded.intensity),
                                              speed: UInt8(appearance.bounded.speed),
                                              travel: UInt8(appearance.bounded.travel),
                                              reduceMotion: frozen, nowMs: milliseconds)
                context.draw(Image(uiImage: material), in: CGRect(x: 0, y: 0, width: 466, height: 350))
                var route = Path()
                route.move(to: CGPoint(x: 207, y: 300))
                route.addLine(to: CGPoint(x: 207, y: 138))
                route.addQuadCurve(to: CGPoint(x: 231, y: 114), control: CGPoint(x: 207, y: 114))
                route.addLine(to: CGPoint(x: 318, y: 114))
                route.addQuadCurve(to: CGPoint(x: 348, y: 94), control: CGPoint(x: 339, y: 114))
                route.addLine(to: CGPoint(x: 362, y: 65))
                context.stroke(route, with: .color(Color(red: 39/255, green: 48/255, blue: 52/255)),
                               style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                context.stroke(route, with: .color(.white), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                var rider = Path()
                rider.move(to: CGPoint(x: 207, y: 275))
                rider.addLine(to: CGPoint(x: 187, y: 315))
                rider.addQuadCurve(to: CGPoint(x: 207, y: 309), control: CGPoint(x: 188, y: 319))
                rider.addQuadCurve(to: CGPoint(x: 227, y: 315), control: CGPoint(x: 224, y: 319))
                rider.closeSubpath()
                context.stroke(rider, with: .color(black), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
                context.fill(rider, with: .color(.white))
                // Exact 72-unit V6 right-arrow master, including the flat stem.
                context.drawLayer { icon in
                    icon.translateBy(x: 125, y: 342); icon.scaleBy(x: 64/72, y: 64/72)
                    var stem = Path(); stem.move(to: CGPoint(x: 20, y: 61)); stem.addLine(to: CGPoint(x: 20, y: 32))
                    stem.addCurve(to: CGPoint(x: 28, y: 24), control1: CGPoint(x: 20, y: 27.5817), control2: CGPoint(x: 23.5817, y: 24))
                    stem.addLine(to: CGPoint(x: 43, y: 24))
                    icon.stroke(stem, with: .color(.white), style: StrokeStyle(lineWidth: 8.6, lineCap: .butt, lineJoin: .round))
                    let points: [CGPoint] = [CGPoint(x:56,y:24), CGPoint(x:54.6,y:26.4), CGPoint(x:37.3,y:38.7),
                        CGPoint(x:36.763,y:39.003),CGPoint(x:36.225,y:39.025),CGPoint(x:35.725,y:38.784),
                        CGPoint(x:35.3,y:38.3),CGPoint(x:35.2,y:37.5),CGPoint(x:38.6,y:28.3),
                        CGPoint(x:38.6,y:19.7),CGPoint(x:35.2,y:10.5),CGPoint(x:35.3,y:9.7),
                        CGPoint(x:35.725,y:9.216),CGPoint(x:36.225,y:8.975),CGPoint(x:36.763,y:8.997),
                        CGPoint(x:37.3,y:9.3),CGPoint(x:54.6,y:21.6)]
                    var tip=Path();tip.addLines(points);tip.closeSubpath();icon.fill(tip,with:.color(.white))
                    icon.stroke(tip,with:.color(.white),style:StrokeStyle(lineWidth:1,lineJoin:.round))
                }
                context.draw(Text("300").font(.system(size: 56, weight: .bold)).foregroundColor(.white),
                             at: CGPoint(x: 196, y: 370), anchor: .leading)
                context.draw(Text("m").font(.system(size: 20)).foregroundColor(.gray), at: CGPoint(x: 301, y: 385), anchor: .leading)
                context.draw(Text("TURN RIGHT").font(.system(size: 12, weight: .medium)).tracking(1.3).foregroundColor(.gray),
                             at: CGPoint(x: 245, y: 410))
                var arc = Path(); arc.addArc(center: CGPoint(x: 233, y: 233), radius: 218,
                                             startAngle: .degrees(55), endAngle: .degrees(125), clockwise: false)
                context.stroke(arc, with: .color(Color(red: 58/255, green: 70/255, blue: 74/255)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            .clipShape(Circle())

        }
    }
}
