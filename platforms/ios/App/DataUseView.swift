import SwiftUI

/// Available without a connection so data use can be reviewed offline.
struct DataUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("位置与路线") {
                    Text("地点搜索、规划和重新规划路线时，搜索内容及所需位置会直接发送给百度地图。路线是驾车路线，优先避开高速，不保证符合摩托车通行规则。")
                    Text("导航期间，定位用于更新路线和圆屏指引；锁屏或切换应用后仍可继续。结束导航会停止导航定位。可在系统设置中调整权限。")
                }
                Section("蓝牙与音乐") {
                    Text("连接圆屏后，导航、速度和已保存的周边地图通过蓝牙同步。允许媒体资料库权限后，Apple Music 的曲名、歌手和播放状态也会同步到圆屏。")
                    Text("音乐信息不发送给百度地图。拒绝音乐权限不影响地点搜索和导航。")
                }
                Section("存储与清理") {
                    Text("最近地点、蓝牙设备标识和百度 iOS AK 保存在手机上。首页可清空最近搜索；删除 App 可移除本地数据。系统备份可能包含部分本地数据。")
                    Text("百度地图对服务请求的处理和保留方式请参阅其隐私政策。此版本无需个人云网关。")
                }
                Section {
                    Link("百度地图开放平台隐私政策", destination: URL(string: "https://lbs.baidu.com/pages/privacy/")!)
                    Link("Apple 隐私政策", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                    Link("OpenStreetMap 数据与许可", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                } header: {
                    Text("第三方服务")
                } footer: {
                    Text("导航路线由百度地图提供；内置济南演示周边地图使用 OpenStreetMap 数据。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("隐私与数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("privacy-data-done")
                }
            }
        }
    }
}
