> **Language:** English · [中文](README.md)

# iPhone companion app: direct Baidu Maps edition

The iPhone app now uses Baidu Maps iOS SDK 7.2.0 for place suggestions, driving route planning, and rerouting. It keeps the existing SwiftUI screens, C++ NavCore, and Waveshare ESP32-S3 BLE display protocol. No personally hosted gateway needs to stay online.

This is a **car driving** route with a no-highways preference, not a motorcycle-specific route. The rider must check local road restrictions. Searching and planning require mobile internet. The route preview is a schematic drawn from Baidu route coordinates; nationwide surrounding map downloads are currently unavailable. The bundled Jinan demo map remains available.

The app asks the user to accept Baidu SDK privacy terms and enter their own iOS AK at first launch. The AK stays on the phone. The final installed bundle identifier must match the Baidu console security code: `com.liuxd2010skyline.motogps`.

On Windows, run the fork's **Actions → Build iPhone app (unsigned IPA)** workflow and download the artifact. The resulting IPA is unsigned and still needs a valid Apple signing and installation method. A configuration profile alone cannot sign an unsigned app.

For local Mac development, install Xcode 16, XcodeGen 2.46.0, and CocoaPods, then run:

```sh
cd platforms/ios
xcodegen generate
pod install
open MotoGPS.xcworkspace
```

The build workflow pins the SDK version, checks key SDK binary hashes, and runs CodeQL on the project's Swift/C++ source. CodeQL cannot inspect the proprietary SDK binaries. Real-device checks of AK authentication, route geometry, turn instructions, background location and BLE display are still required.
