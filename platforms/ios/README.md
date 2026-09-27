> **语言 / Language:** 中文 · [English](README.en.md)

# iPhone 伴侣 App：百度地图直连版

这个分支的手机端直接使用百度地图 iOS SDK 搜索地点、规划驾车路线及偏航后重新规划。原有 SwiftUI 首页、路线选择、导航状态、C++ NavCore 和微雪圆屏 BLE 协议继续使用。无需部署或常开个人网关。

## 使用范围

- iOS 17 或更新版本。手机必须联网才能搜索及规划新路线；圆屏用蓝牙连接手机。
- 路线来源是百度**驾车**路线，当前选择“避开高速”策略，不是摩托车专用路线。实际道路通行限制需自行核对。
- 路线预览绘制百度返回的坐标示意图，不请求 Apple 地图底图。当前没有全国周边道路/建筑的在线地图和离线下载；内置济南演示地图仍可用于演示。
- AK 由使用者在 App 首次打开时填写，保存在手机本地，不需要提交到 GitHub。首次使用前必须在 App 中确认百度 SDK 隐私说明。
- 工程的 Bundle ID 是 `com.liuxd2010skyline.motogps`，必须与百度控制台 iOS AK 的安全码一致。安装工具如改写 Bundle ID，AK 鉴权会失败。

## Windows 电脑生成未签名 IPA

本仓库的 GitHub Actions 工作流 `.github/workflows/ios-ipa.yml` 使用 GitHub 提供的 macOS 构建机。Windows 电脑只需在网页中运行该工作流：

1. 打开自己 fork 的 **Actions → Build iPhone app (unsigned IPA) → Run workflow**。
2. 等待绿色成功标志，从运行结果的 **Artifacts** 下载 ZIP 并解压，得到 `MotoGPS-unsigned.ipa` 与 `SHA256SUMS.txt`。
3. 这个 IPA **未签名**，不能直接点开安装。需使用合法的个人开发签名或其他 Apple 允许的分发方式。配置描述文件本身无法替未签名 App 签名。
4. 安装后首次启动，阅读隐私说明，粘贴自己的百度 iOS AK，再搜索目的地。

如果 iOS 源码变更导致构建被“Block changes to iPhone source until reviewed”停止，需要先审查差异，再更新该工作流锁定的 iOS Git tree ID。不能直接删掉安全检查。

## Mac 本地开发

需要 Xcode 16、XcodeGen 2.46.0 和 CocoaPods。进入 `platforms/ios` 后运行：

```sh
xcodegen generate
pod install
open MotoGPS.xcworkspace
```

请打开 `MotoGPS.xcworkspace`，不是生成的 `.xcodeproj`。选择自己的 Apple Team 和设备后再签名运行。Podfile 固定百度地图 SDK 7.2.0；构建工作流检查下载后的关键 SDK 二进制 SHA-256，并扫描本项目的 Swift/C++ 源码。CodeQL 无法审查百度专有二进制的内部代码。

## 数据流

```text
输入目的地 / 手机位置 → 百度地图 iOS SDK → GCJ-02 驾车路线
                                           ↓
                               原 NavCore 跟踪 / 转向 / 偏航
                                           ↓
                              BLE → 微雪 ESP32-S3 圆屏
```

手机 GPS 位置为 WGS84。向百度 SDK 请求前转换为 GCJ-02；百度返回的路线按 GCJ-02 交给原有导航核心。地点搜索结果需逆变换为 WGS84，供现有位置与目的地模型使用。

本版尚需在真机上核对百度 AK 鉴权、路线几何、实际转向提示、锁屏后台定位和圆屏显示。成功构建不等于完成实车验证；首次验证请在静止安全环境进行。
