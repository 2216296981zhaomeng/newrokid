# Rokid-Glass iOS Plugin Build Notes

This standalone plugin copy lives in `D:\chajian\Rokid`. Its DCloud plugin id is still `Rokid-Glass`, but this directory is iOS-only. Do not use it to overwrite the project's Android plugin files.

The iOS bridge source is in `ios/Classes`. In `agent-app3.0`, the matching target path is `nativeplugins/Rokid-Glass/ios/Classes`.

## Current iOS Package

The project keeps one cross-platform plugin named `Rokid-Glass`, but this standalone folder only contains the iOS side:

- Android in `agent-app3.0/nativeplugins/Rokid-Glass` should be left unchanged.
- iOS uses `RokidCXRLModule`, with the CXR-L SDK bridge in `RokidCXRLUniPlugin.framework` plus the Objective-C uni module source in `ios/Classes`.

The iOS framework set expected in `nativeplugins/Rokid-Glass/ios` is:

- `RokidCXRLUniPlugin.framework`
- `RGCxrClient.framework`
- `RGCoreKit.framework`
- `CocoaLumberjack.framework`

The JS layer still calls `uni.requireNativePlugin('Rokid-Glass')`.

The Objective-C module layer also exposes teleprompter convenience methods:

- `prepareTeleprompter(options, callback)`: initializes SDK, requests Rokid authorization, connects CustomView, and opens the teleprompter view.
- `updateTeleprompter(options, callback)`: updates the `textView` content on the glasses.
- `closeTeleprompter(options, callback)`: closes the CustomView teleprompter scene.

Important: `RGCxrClient.framework` imports `RGCoreKit`. Both dynamic frameworks must stay in `nativeplugins/Rokid-Glass/ios` and in `frameworks`/`embedFrameworks` in `package.json`; otherwise the app can launch-crash before any Vue page runs.

## Enabling Real iOS

Build a wrapper framework on macOS first. If the error is similar to one of these, the wrapper/dependencies are incomplete:

- `RokidGlass-Swift.h file not found`
- `No such module RGCxrClient`
- `No such module RGCoreKit`
- `Undefined symbols for architecture arm64`
- launch crash: `dyld: Library not loaded: ... RGCoreKit ...`

Build steps on macOS:

1. Create an iOS Framework target named `RokidCXRLUniPlugin` or keep the product name aligned with `package.json`.
2. Set iOS Deployment Target to `16.0`, matching the current Rokid SDK binaries.
3. Set Product Module Name to `RokidCXRLUniPlugin` if you keep the current package declaration.
4. Enable `BUILD_LIBRARY_FOR_DISTRIBUTION = YES`.
5. Add these files to the framework target:
   - `ios/Classes/RokidGlassModule.h`
   - `ios/Classes/RokidGlassModule.m`
   - `ios/Classes/RokidGlassBridge.swift`
   - `ios/Classes/RokidGlassPluginProxy.swift`
6. Add CocoaPods dependencies from Rokid sample:
   - `pod 'RGCxrClient'`
   - `pod 'RGCoreKit'`
7. Build Release for a real iPhone device.
8. Copy the built wrapper framework and the resolved dynamic dependencies to `nativeplugins/Rokid-Glass/ios/`.
9. Keep every copied dynamic framework in `frameworks` and `embedFrameworks` in `nativeplugins/Rokid-Glass/package.json`. At minimum this currently means `RokidCXRLUniPlugin.framework`, `RGCxrClient.framework`, `RGCoreKit.framework`, and `CocoaLumberjack.framework`.

For a lower-iOS App Store build, every embedded framework must support the same deployment target. If `RGCxrClient.framework` is still built for iOS 16.0, changing only the app or plugin `deploymentTarget` is not enough; rebuild or replace the Rokid SDK framework first.

The source code keeps the existing JS method names and adds teleprompter helpers:

- `requestAuthorization`
- `connectCustomView`
- `openCustomView`
- `updateCustomView`
- `startAudioRecord`
- `stopAudioRecord`
- `prepareTeleprompter`
- `updateTeleprompter`
- `closeTeleprompter`

Realtime teleprompter audio uses `audioChunk` events with 16 kHz, 16-bit, mono PCM base64 payload.
