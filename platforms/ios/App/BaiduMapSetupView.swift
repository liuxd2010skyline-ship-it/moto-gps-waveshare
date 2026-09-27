import SwiftUI

struct BaiduMapSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BaiduMapSetup.privacyKey) private var accepted = false
    @AppStorage(BaiduMapSetup.akKey) private var savedAK = ""
    @State private var draftAK = ""
    @State private var agrees = false

    var body: some View {
        NavigationStack {
            Form {
                Section("百度地图服务") {
                    Text("MOTO GPS 会直接从百度地图获取地点、驾车路线和路况，手机通过蓝牙把导航信息传给圆屏。无需常开的个人网关。")
                    Text("当前使用的是驾车路线，并优先避开高速。它不是摩托车专用路线；骑行时请以当地交通规则及道路标志为准。")
                }
                Section("你的 iOS AK") {
                    TextField("粘贴百度地图 iOS AK", text: $draftAK)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("baidu-ak-input")
                    Text("AK 只保存在本机，不写入公开仓库。百度控制台中填写的安全码必须与安装后的 App Bundle ID 一致：com.liuxd2010skyline.motogps。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("隐私同意") {
                    Text("搜索时，关键词和附近位置会发给百度；规划及偏航重算时，起终点位置会发给百度。导航期间手机定位会更新路线和圆屏指引。")
                    Link("查看百度地图开放平台隐私政策", destination: URL(string: "https://lbs.baidu.com/pages/privacy/")!)
                    Toggle("我已阅读并同意使用百度地图 SDK", isOn: $agrees)
                }
            }
            .navigationTitle("百度地图配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if accepted && !savedAK.isEmpty {
                        Button("取消") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let key = draftAK.trimmingCharacters(in: .whitespacesAndNewlines)
                        savedAK = key
                        accepted = true
                        dismiss()
                    }
                    .disabled(!agrees || draftAK.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("baidu-setup-save")
                }
            }
        }
        .onAppear {
            draftAK = savedAK
            agrees = accepted
        }
    }
}
