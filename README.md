# Rokid-Glass iOS Native Plugin

这是给 `agent-app3.0` 使用的 DCloud/uni-app iOS 原生插件，插件 ID 为 `Rokid-Glass`。iOS 侧基于 Rokid CXR-L SDK，完成授权、CustomView 会话准备和眼镜提词器更新。

## 目录

- `package.json`: DCloud iOS 原生插件声明。
- `ios/Classes`: uni-app 模块入口和提词器快捷接口。
- `ios/*.framework`: iOS 真机依赖，包含 `RokidCXRLUniPlugin.framework`、`RGCxrClient.framework`、`RGCoreKit.framework`、`CocoaLumberjack.framework`。
- `tools/ios`: macOS 构建和打包脚本。
- `docs`: iOS 构建、云打包和 WebSocket 音频说明。

## uni-app 调用

```js
const rokid = uni.requireNativePlugin('Rokid-Glass')

rokid.setEventCallback((event) => {
  console.log('rokid event', event)
})

rokid.prepareTeleprompter({
  appName: '宅喔经纪人',
  bundleId: 'com.tcwang.agent',
  title: 'AI提词器',
  text: '已连接，等待开始AI场景...',
  nativeAuthTimeout: 110
}, (res) => {
  console.log('prepareTeleprompter', res)
})

rokid.updateTeleprompter({
  text: '客户重点：关注学区、预算和付款周期'
}, (res) => {
  console.log('updateTeleprompter', res)
})

rokid.closeTeleprompter({}, (res) => {
  console.log('closeTeleprompter', res)
})
```

也可以继续使用底层接口：

- `initSDK`
- `requestAuthorization`
- `connectCustomView`
- `openCustomView`
- `updateCustomView`
- `closeCustomView`
- `startAudioRecord`
- `stopAudioRecord`
- `startPhoneAudioRecord`
- `stopPhoneAudioRecord`
- `handleOpenURL`
- `release`

## 链路对应

1. 手机应用集成 SDK：插件通过 `package.json` 和 `ios/*.framework` 集成 CXR-L SDK。
2. 授权获取 token：`requestAuthorization` 或 `prepareTeleprompter` 会拉起 Rokid AI App 授权。
3. 建立 CustomView 会话：`connectCustomView` 和 `openCustomView` 负责打开眼镜端提词视图。
4. 选择 AI 场景后更新提词：页面根据业务场景调用 `updateTeleprompter({ text })` 或 `updateCustomView({ updateJson })`。

## 导入项目

目标项目当前安卓插件已可用，不建议直接用这个 iOS-only 目录覆盖 `nativeplugins/Rokid-Glass`。同步项目时只覆盖这些内容：

- `ios/Classes/*`
- `ios/*.framework` 中你重新编译或解析出的 iOS framework
- `package.json` 的 `_dp_nativeplugin.ios` 部分
- `docs` 中的 iOS 构建说明

项目现有的 `utils/rokidGlass.js` 已按插件名 `Rokid-Glass` 调用，低层接口可以直接兼容。新增的 `prepareTeleprompter/updateTeleprompter/closeTeleprompter` 是便捷接口，适合后续把页面逻辑进一步收敛到插件侧。

## iOS 注意事项

- 当前声明按 arm64 真机包处理，`deploymentTarget` 是 iOS 16.0。
- URL 回调 Scheme 为 `cxrl://auth/callback`，已写入 `package.json` 的 `CFBundleURLTypes`。
- `RokidCXRLUniPlugin.framework`、`RGCxrClient.framework`、`RGCoreKit.framework`、`CocoaLumberjack.framework` 都需要随包嵌入。
- 如需修改 Swift 桥内部逻辑，需要在 macOS 上重建 `RokidCXRLUniPlugin.framework`，再替换 `ios/` 下的 framework。

## GitHub Actions 编译

仓库包含 `.github/workflows/ios-framework.yml`。推送到 `main` 或手动运行 `Build iOS Framework` 后，Actions 会：

1. 使用 `macos-26` runner 和 iOS 16.0 deployment target。
2. 从 `ios/Classes` 编译 `RokidCXRLUniPlugin.framework`。
3. 打包 `dist/Rokid-Glass-ios-nativeplugin.zip`。
4. 上传 artifact：`Rokid-Glass-iOS-<run_number>`。

下载 artifact 后，把其中的 `RokidCXRLUniPlugin.framework` 替换到 `agent-app3.0/nativeplugins/Rokid-Glass/ios/`，或直接使用压缩包里的 DCloud 原生插件目录。
