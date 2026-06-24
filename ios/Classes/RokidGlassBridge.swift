import Foundation
import UIKit
import Combine
import AVFoundation
import RGCxrClient

public typealias RokidGlassCallback = (_ result: Any?, _ keepAlive: Bool) -> Void

@objc(RokidGlassBridge)
@objcMembers
public final class RokidGlassBridge: NSObject {
    public static let shared = RokidGlassBridge()

    private static var initialized = false
    private static var initializedSessionType = "customView"

    private let client: RGCxrClient = CxrClient.shared
    private let bridgeVersion = "ios-cxrl-1.0.14-customview-icon-20260624"
    private var cancellables = Set<AnyCancellable>()
    private var eventCallback: RokidGlassCallback?
    private var pendingAuthorizationCallback: RokidGlassCallback?
    private var authorizationRequestId: Int64 = 0
    private var completedAuthorizationRequestId: Int64 = 0

    private var token = ""
    private var sessionId = ""
    private var deviceName = ""
    private var sessionType = "customView"
    private var packageName = "com.rokid.cxrswithcxrl"
    private var appActivityName = "com.rokid.cxrswithcxrl.activities.main.MainActivity"
    private var appDisplayName = "宅喔经纪人"
    private var iosBundleId = "com.tcwang.agent"
    private var iosPageName = "com.tcwang.agent"
    private var sceneReady = false
    private var audioStarted = false
    private var audioCodecType = -1
    private var audioSceneId = -1
    private var audioType = "agent"
    private var customViewOpenRequestId: Int64 = 0
    private var lastCustomViewStage = "idle"
    private var lastCustomViewVariant = ""
    private var lastCustomViewErrorCode = -1
    private var lastCustomViewMessage = ""
    private var lastCustomViewJson = ""
    private var lastCustomViewJsonBytes = 0

    private let audioQueue = DispatchQueue(label: "com.zhaiwo.agent.rokid.ios.audio")
    private var pcmFileHandle: FileHandle?
    private var pcmPath = ""
    private var wavPath = ""
    private var audioBytes = 0
    private var audioChunkCount = 0
    private var audioSessionId: Int64 = 0
    private var audioRealtimeBuffer = Data()
    private var audioRealtimeSeq = 0
    private var lastAudioEmitAt = Date.distantPast
    private var nativeAudioUploader: RokidNativeAudioUploader?
    private var nativeAudioUploadEnabled = false
    private var nativeAudioUploadState = "idle"
    private var nativeAudioUploadError = ""
    private var nativeAudioEnqueuedBytes = 0
    private var nativeAudioDroppedBytes = 0
    private var nativeAudioSentBytes = 0
    private var nativeAudioSentChunks = 0
    private var phoneAudioEngine: AVAudioEngine?
    private var phoneAudioConverter: AVAudioConverter?
    private var phoneAudioStarted = false
    private var phoneAudioSource = "rokid_cxr_audio_callback"

    private let sampleRate = 16000
    private let channels = 1
    private let bitsPerSample = 16
    private let realtimeMinBytes = 6400
    private let realtimeMaxInterval: TimeInterval = 0.25

    public override init() {
        super.init()
        bindEvents()
    }

    @objc(sharedInstance)
    public static func sharedInstance() -> RokidGlassBridge {
        return shared
    }

    public func setEventCallback(_ callback: RokidGlassCallback?) {
        eventCallback = callback
        invokeKeepAlive(callback, ok(stateJson().merging([
            "event": "nativeBridgeReady",
            "bridge": "RokidGlassBridge",
            "bridgeVersion": bridgeVersion
        ]) { _, new in new }))
    }

    public func initSDK(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        let nextType = stringOption(options, "sessionType", stringOption(options, "mode", sessionType))
        sessionType = nextType == "customApp" ? "customApp" : "customView"
        applyIdentity(options)
        initializeIfNeeded(sessionType, options: options)
        invoke(callback, ok(stateJson().merging([
            "rokidAIAppInstalled": client.isRokidAppInstalled(),
            "iosInitializedSessionType": Self.initializedSessionType,
            "iosBundleId": iosBundleId,
            "iosPageName": iosPageName
        ]) { _, new in new }))
    }

    public func checkPermissions(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        invoke(callback, ok(stateJson().merging([
            "rokidAIAppInstalled": client.isRokidAppInstalled()
        ]) { _, new in new }))
    }

    public func requestAuthorization(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        applyIdentity(options)
        initializeIfNeeded(sessionType, options: options)
        guard client.isRokidAppInstalled() else {
            invoke(callback, error(1002, "Rokid AI App is not installed"))
            return
        }

        let requireSessionId = boolOption(options, "requireSessionId", false)
        let forceReauthorize = boolOption(options, "forceReauthorize", boolOption(options, "forceAuthorization", false))
        if forceReauthorize {
            client.auth.clearAuthentication()
            token = ""
            sessionId = ""
            deviceName = currentDeviceName()
            emit("authorizationState", stateJson().merging([
                "message": "forceReauthorize"
            ]) { _, new in new })
        }

        let cachedSessionId = client.auth.currentSessionId ?? sessionId
        if client.auth.isAuthenticated() && (!requireSessionId || !cachedSessionId.isEmpty || !forceReauthorize) {
            token = client.auth.currentToken ?? token
            sessionId = cachedSessionId
            deviceName = client.auth.currentDeviceName ?? currentDeviceName()
            var payload = authorizationPayload()
            if requireSessionId && cachedSessionId.isEmpty {
                payload["authSessionMissing"] = true
                payload["message"] = "sessionIdMissing"
                emit("authorizationState", payload)
            }
            invoke(callback, ok(payload))
            return
        }
        if client.auth.isAuthenticated() && forceReauthorize && requireSessionId && cachedSessionId.isEmpty {
            client.auth.clearAuthentication()
            token = ""
            sessionId = ""
            deviceName = currentDeviceName()
            emit("authorizationState", stateJson().merging([
                "message": "sessionIdMissingReauthorize"
            ]) { _, new in new })
        }

        authorizationRequestId += 1
        let requestId = authorizationRequestId
        completedAuthorizationRequestId = 0
        pendingAuthorizationCallback = callback

        let appName = stringOption(options, "appName", appDisplayName)
        let requestBundleId = stringOption(options, "bundleId", stringOption(options, "iosBundleId", iosBundleId))
        let scopes = stringArrayOption(options, "scopes", ["device_control", "audio_stream"])
        let nativeTimeout = max(15, intOption(options, "nativeAuthTimeout", 75))
        client.auth.authenticate(
            scopes: scopes,
            bundleId: requestBundleId.isEmpty ? nil : requestBundleId,
            appName: appName
        ) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let auth):
                    self.completeAuthorizationSuccess(requestId, token: auth.0, sessionId: auth.1, deviceName: self.currentDeviceName())
                case .failure(let authError):
                    self.completeAuthorizationFailure(requestId, message: authError.localizedDescription)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(nativeTimeout)) { [weak self] in
            self?.completeAuthorizationFailure(requestId, message: "Rokid authorization callback timeout after \(nativeTimeout)s")
        }
    }

    public func connectCustomView(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        sessionType = "customView"
        applyIdentity(options)
        initializeIfNeeded(sessionType, options: options)
        invoke(callback, ok(stateJson()))
    }

    public func connectCustomApp(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        sessionType = "customApp"
        applyIdentity(options)
        initializeIfNeeded(sessionType, options: options)
        invoke(callback, ok(stateJson()))
    }

    public func openCustomView(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        guard ensureAuthenticated(callback) else { return }
        sessionType = "customView"
        applyIdentity(options)
        initializeIfNeeded(sessionType, options: options)
        let title = stringOption(options, "title", "宅喔带看")
        let text = stringOption(options, "text", "眼镜端场景已打开")
        let requestedViewJson = stringOption(options, "viewJson", defaultCustomViewJson(title: title, text: text))
        let variants = customViewOpenVariants(options: options, requestedViewJson: requestedViewJson, title: title, text: text)
        customViewOpenRequestId += 1
        let requestId = customViewOpenRequestId
        sceneReady = false
        lastCustomViewStage = "preparing"
        lastCustomViewVariant = ""
        lastCustomViewErrorCode = -1
        lastCustomViewMessage = ""
        lastCustomViewJsonBytes = 0
        emit("customViewOpening", customViewPayload(extra: [
            "variantCount": variants.count,
            "closeBeforeOpen": boolOption(options, "closeBeforeOpen", true)
        ]))

        let closeBeforeOpen = boolOption(options, "closeBeforeOpen", true)
        if closeBeforeOpen {
            lastCustomViewStage = "closingBeforeOpen"
            client.closeCustomView(defaultCustomViewJson(title: title, text: "")) { [weak self] success in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    guard requestId == self.customViewOpenRequestId else { return }
                    if self.lastCustomViewStage == "closingBeforeOpen" {
                        self.lastCustomViewStage = success ? "closedBeforeOpen" : "closeBeforeOpenFailed"
                    }
                    self.emit("customViewPreclose", self.customViewPayload(extra: [
                        "success": success
                    ]))
                }
            }
        }
        let delayMs = closeBeforeOpen ? max(250, intOption(options, "openDelayMs", 600)) : max(0, intOption(options, "openDelayMs", 0))
        let attemptTimeoutMs = max(1500, min(12000, intOption(options, "openAttemptTimeoutMs", 6000)))
        let beginOpen = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(delayMs) / 1000.0)) { [weak self] in
                self?.openCustomViewVariant(
                    requestId: requestId,
                    variants: variants,
                    index: 0,
                    callback: callback,
                    attemptTimeoutMs: attemptTimeoutMs
                )
            }
        }
        uploadDefaultCustomViewIconsIfNeeded(options, completion: beginOpen)
    }

    public func updateCustomView(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        guard ensureAuthenticated(callback) else { return }
        let updateJson = stringOption(options, "updateJson", defaultUpdateJson(text: stringOption(options, "text", "Updated")))
        client.updateCustomView(updateJson) { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.emit(success ? "customViewUpdated" : "customViewError", self.stateJson())
                self.invoke(callback, success ? self.ok(self.stateJson()) : self.error(1003, "updateCustomView failed"))
            }
        }
    }

    public func closeCustomView(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        let fallbackJson = lastCustomViewJson.isEmpty ? defaultCustomViewJson(title: "宅喔带看", text: "") : lastCustomViewJson
        let viewJson = stringOption(options, "viewJson", fallbackJson)
        customViewOpenRequestId += 1
        lastCustomViewStage = "closing"
        lastCustomViewVariant = "close"
        lastCustomViewErrorCode = -1
        lastCustomViewMessage = ""
        lastCustomViewJson = viewJson
        lastCustomViewJsonBytes = viewJson.data(using: .utf8)?.count ?? 0
        emit("customViewClosing", customViewPayload())
        client.closeCustomView(viewJson) { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.sceneReady = false
                if success {
                    self.lastCustomViewStage = "closed"
                    self.lastCustomViewErrorCode = -1
                    self.lastCustomViewMessage = ""
                    self.lastCustomViewJson = ""
                } else {
                    self.lastCustomViewStage = "closeFailed"
                    self.lastCustomViewErrorCode = 1003
                    self.lastCustomViewMessage = "closeCustomView failed"
                }
                let payload = self.customViewPayload(extra: ["success": success])
                self.emit(success ? "customViewClosed" : "customViewError", payload)
                self.invoke(callback, success ? self.ok(payload) : self.error(1003, self.lastCustomViewMessage))
            }
        }
    }

    public func queryApp(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        guard ensureAuthenticated(callback) else { return }
        applyIdentity(options)
        initializeIfNeeded("customApp", options: options)
        client.queryApp { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let payload = self.stateJson().merging([
                    "success": success,
                    "appInstalled": success
                ]) { _, new in new }
                self.emit("queryApp", payload)
                self.invoke(callback, self.ok(payload))
            }
        }
    }

    public func openApp(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        guard ensureAuthenticated(callback) else { return }
        sessionType = "customApp"
        applyIdentity(options)
        initializeIfNeeded(sessionType, options: options)
        let activityName = stringOption(options, "activityName", stringOption(options, "entry", appActivityName))
        let url = stringOption(options, "url", "")
        client.openApp(activityName: activityName, url: url) { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.sceneReady = success
                let payload = self.stateJson().merging([
                    "success": success,
                    "activityName": activityName,
                    "url": url
                ]) { _, new in new }
                self.emit(success ? "customAppOpened" : "customAppOpenFailed", payload)
                self.invoke(callback, success ? self.ok(payload) : self.error(1003, "openApp failed"))
            }
        }
    }

    public func stopApp(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        client.stopApp { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if success { self.sceneReady = false }
                let payload = self.stateJson().merging([
                    "success": success
                ]) { _, new in new }
                self.emit("customAppClosed", payload)
                self.invoke(callback, success ? self.ok(payload) : self.error(1003, "stopApp failed"))
            }
        }
    }

    public func changeAudioSceneId(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        let scene = audioSceneOption(options, defaultValue: .conference)
        audioSceneId = scene.rawValue
        client.changeAudioSceneId(scene) { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let payload = self.stateJson().merging([
                    "audioSceneId": scene.rawValue,
                    "audioScene": self.audioSceneName(scene),
                    "success": success
                ]) { _, new in new }
                self.emit(success ? "audioSceneChanged" : "audioSceneChangeFailed", payload)
                self.invoke(callback, success ? self.ok(payload) : self.error(1006, "changeAudioSceneId failed"))
            }
        }
    }

    public func startAudioRecord(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        guard ensureAuthenticated(callback) else { return }
        if phoneAudioStarted {
            _ = stopPhoneAudioEngine(reason: "switchToGlassesAudio")
        }
        let nextType = stringOption(options, "sessionType", stringOption(options, "mode", sessionType))
        if nextType == "customApp" {
            sessionType = "customApp"
        }
        applyIdentity(options)
        initializeIfNeeded(sessionType, options: options)
        audioType = stringOption(options, "iosRecordType", stringOption(options, "recordType", stringOption(options, "type", "test")))
        audioCodecType = intOption(options, "codecType", 1)
        let scene = audioSceneOption(options, defaultValue: .conference)
        audioSceneId = scene.rawValue
        let useNativeUpload = boolOption(options, "nativeUpload", false)
        let nativeWsUrl = stringOption(options, "wsUrl", "")
        if useNativeUpload && nativeWsUrl.isEmpty {
            invoke(callback, error(1004, "wsUrl is required when nativeUpload is true"))
            return
        }
        if audioStarted || nativeAudioUploadEnabled {
            client.stopRecord(audioType)
            _ = finalizeAudioStop(reason: "restart", sendStop: false, uploadWait: 2.0)
        }
        guard resetAudioBuffers() else {
            audioCodecType = -1
            nativeAudioUploadEnabled = false
            invoke(callback, error(1005, "Failed to create audio file"))
            return
        }
        nativeAudioUploadEnabled = useNativeUpload
        if useNativeUpload {
            startNativeAudioUpload(options, session: audioSessionId)
        } else {
            stopNativeAudioUpload(sendStop: false, wait: 1.0)
        }
        audioStarted = true
        emit("startAudioRecordInvoked", stateJson().merging([
            "recordType": audioType,
            "codec": "pcm",
            "codecType": audioCodecType,
            "audioCodecType": audioCodecType,
            "audioSceneId": scene.rawValue,
            "audioScene": audioSceneName(scene),
            "mode": "antClose",
            "nativeUpload": useNativeUpload,
            "bleConnected": RGCxrClientBLE.shared.isConnected,
            "connectedDeviceName": RGCxrClientBLE.shared.connectedDeviceName ?? ""
        ]) { _, new in new })
        if boolOption(options, "changeAudioScene", false) {
            client.changeAudioSceneId(scene) { [weak self] success in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.emit(success ? "audioSceneChanged" : "audioSceneChangeFailed", self.stateJson().merging([
                        "audioSceneId": scene.rawValue,
                        "audioScene": self.audioSceneName(scene),
                        "success": success
                    ]) { _, new in new })
                }
            }
        }
        client.startRecord(audioType, codec: .pcm, mode: .antClose)
        emit("audioStateChanged", stateJson())
        invoke(callback, ok(stateJson().merging([
            "pcmPath": pcmPath,
            "sampleRate": sampleRate,
            "channels": channels,
            "bitsPerSample": bitsPerSample,
            "recordType": audioType,
            "nativeUpload": useNativeUpload
        ]) { _, new in new }))
    }

    public func stopAudioRecord(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        if phoneAudioStarted {
            let data = stopPhoneAudioEngine(reason: "apiStop")
            invoke(callback, ok(data))
            return
        }
        if audioStarted {
            client.stopRecord(audioType)
        }
        let data = finalizeAudioStop(reason: "apiStop", sendStop: true, uploadWait: 5.0)
        invoke(callback, ok(data))
    }

    public func startPhoneAudioRecord(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        let session = AVAudioSession.sharedInstance()
        let startBlock = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                do {
                    let payload = try self.startPhoneAudioEngine(options)
                    self.invoke(callback, self.ok(payload))
                } catch {
                    self.invoke(callback, self.error(1010, error.localizedDescription))
                }
            }
        }

        switch session.recordPermission {
        case .granted:
            startBlock()
        case .denied:
            invoke(callback, error(1010, "Microphone permission denied"))
        case .undetermined:
            session.requestRecordPermission { granted in
                if granted {
                    startBlock()
                } else {
                    DispatchQueue.main.async {
                        self.invoke(callback, self.error(1010, "Microphone permission denied"))
                    }
                }
            }
        @unknown default:
            startBlock()
        }
    }

    public func stopPhoneAudioRecord(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        let data = stopPhoneAudioEngine(reason: "apiStop")
        invoke(callback, ok(data))
    }

    public func isBluetoothConnected(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        invoke(callback, ok(stateJson().merging(["connected": client.auth.isAuthenticated()]) { _, new in new }))
    }

    public func requestSystemInfo(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        invoke(callback, ok(stateJson().merging([
            "platform": "ios",
            "sdk": "RGCxrClient"
        ]) { _, new in new }))
    }

    public func requestGlassDeviceInfo(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        deviceName = currentDeviceName()
        invoke(callback, ok(stateJson().merging([
            "platform": "ios",
            "glassIdSource": currentGlassId().isEmpty ? "unavailable" : "connectedDeviceName",
            "glassIdStable": false
        ]) { _, new in new }))
    }

    public func getState(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        invoke(callback, ok(stateJson()))
    }

    public func releaseSession(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        if phoneAudioStarted {
            _ = stopPhoneAudioEngine(reason: "release")
        }
        if audioStarted {
            client.stopRecord(audioType)
        }
        _ = finalizeAudioStop(reason: "release", sendStop: true, uploadWait: 3.0)
        sceneReady = false
        audioCodecType = -1
        invoke(callback, ok(stateJson()))
    }

    public static func handleOpenURL(_ url: URL) -> Bool {
        bootstrapDefault()
        let client = CxrClient.shared
        if client.handleOpenURL(url) {
            return true
        }
        return client.auth.handleCallback(url: url)
    }

    public func handleOpenURL(_ options: NSDictionary?, callback: RokidGlassCallback?) {
        let urlString = stringOption(options, "url", "")
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            invoke(callback, error(1001, "Invalid callback url"))
            return
        }
        let handled = Self.handleOpenURL(url)
        invoke(callback, ok(stateJson().merging([
            "handled": handled,
            "url": urlString
        ]) { _, new in new }))
    }

    public static func bootstrapDefault() {
        guard !initialized else { return }
        CxrClient.initialize(mode: .customView, options: .init(appDisplayName: "宅喔经纪人", pageName: nil))
        initialized = true
        initializedSessionType = "customView"
    }

    private func bindEvents() {
        guard cancellables.isEmpty else { return }

        client.auth.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleAuthEvent(event)
            }
            .store(in: &cancellables)

        client.audioEventPublisher
            .sink { [weak self] event in
                guard let self = self else { return }
                switch event {
                case .started(let info):
                    self.audioQueue.async {
                        self.audioStarted = true
                        self.emit("audioStateChanged", self.stateJson().merging([
                            "codec": "\(info.codec)",
                            "type": "\(info.type)",
                            "channels": "\(info.channels)"
                        ]) { _, new in new })
                    }
                case .stream(let packet):
                    self.audioQueue.async {
                        self.handleAudioData(packet.data, timestamp: packet.timestamp)
                    }
                }
            }
            .store(in: &cancellables)

        client.customViewRunningEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                self.sceneReady = event.isRunning
                self.emit(event.isRunning ? "customViewOpened" : "customViewClosed", self.stateJson())
            }
            .store(in: &cancellables)

        client.appResumeChangeEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.emit("appResume", self?.stateJson().merging([
                    "packageName": event.packageName
                ]) { _, new in new } ?? [:])
            }
            .store(in: &cancellables)

        client.setNotifyEventListenCmds(["rk_custom_key"])
        client.notifyEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                var payload = self.stateJson()
                payload["cmd"] = event.cmd
                payload["subCmd"] = event.subCmd
                if let data = event.payload {
                    payload["base64"] = data.base64EncodedString()
                    payload["text"] = String(data: data, encoding: .utf8) ?? ""
                }
                self.emit("customCommandResult", payload)
            }
            .store(in: &cancellables)
    }

    private func handleAuthEvent(_ event: RGCxrClientAuthEvent) {
        switch event {
        case .authenticationSucceeded(let nextToken, let nextSessionId, let deviceName):
            if pendingAuthorizationCallback != nil {
                completeAuthorizationSuccess(authorizationRequestId, token: nextToken, sessionId: nextSessionId, deviceName: deviceName)
            } else {
                token = nextToken
                sessionId = nextSessionId ?? ""
                self.deviceName = deviceName ?? currentDeviceName()
                emit("authorization", authorizationPayload())
            }
        case .authenticationFailed(let authError):
            if pendingAuthorizationCallback != nil {
                completeAuthorizationFailure(authorizationRequestId, message: "\(authError)")
            } else {
                emit("authorization", stateJson().merging([
                    "message": "\(authError)"
                ]) { _, new in new })
            }
        case .tokenExpired:
            token = ""
            emit("authorization", stateJson().merging(["message": "tokenExpired"]) { _, new in new })
        case .stateChanged(let authState):
            if authState.isAuthenticated, pendingAuthorizationCallback != nil {
                completeAuthorizationSuccess(
                    authorizationRequestId,
                    token: client.auth.currentToken ?? token,
                    sessionId: client.auth.currentSessionId,
                    deviceName: client.auth.currentDeviceName
                )
            } else {
                emit("authorizationState", stateJson())
            }
        }
    }

    private func initializeIfNeeded(_ nextType: String, options: NSDictionary?) {
        if Self.initialized {
            configureAuth(options)
            return
        }
        if nextType == "customApp" {
            CxrClient.initialize(mode: .customApp, options: .init(appDisplayName: appDisplayName, pageName: packageName))
            Self.initializedSessionType = "customApp"
        } else {
            let requestedPageName = stringOption(options, "customViewPageName", stringOption(options, "pageName", stringOption(options, "iosPageName", iosPageName)))
            let pageName = boolOption(options, "useCustomViewPageName", false) ? requestedPageName : ""
            CxrClient.initialize(mode: .customView, options: .init(
                appDisplayName: appDisplayName,
                pageName: pageName.isEmpty ? nil : pageName
            ))
            Self.initializedSessionType = "customView"
        }
        Self.initialized = true
        configureAuth(options)
    }

    private func applyIdentity(_ options: NSDictionary?) {
        appDisplayName = stringOption(options, "appDisplayName", stringOption(options, "appName", appDisplayName))
        iosBundleId = stringOption(options, "bundleId", stringOption(options, "iosBundleId", iosBundleId))
        iosPageName = stringOption(options, "pageName", stringOption(options, "iosPageName", iosPageName.isEmpty ? iosBundleId : iosPageName))
        packageName = stringOption(options, "packageName", packageName)
        appActivityName = stringOption(options, "activityName", stringOption(options, "entry", appActivityName))
    }

    private func configureAuth(_ options: NSDictionary?) {
        var config = client.auth.config
        config.callbackScheme = stringOption(options, "callbackScheme", config.callbackScheme)
        config.callbackHost = stringOption(options, "callbackHost", config.callbackHost)
        config.callbackPath = stringOption(options, "callbackPath", config.callbackPath)
        config.requestTimeout = TimeInterval(max(60, intOption(options, "sdkAuthTimeout", Int(config.requestTimeout))))
        client.auth.config = config
    }

    private func authorizationPayload() -> [String: Any] {
        return stateJson().merging([
            "token": token,
            "sessionId": sessionId,
            "deviceName": deviceName,
            "authenticated": client.auth.isAuthenticated() || !token.isEmpty,
            "iosBundleId": iosBundleId,
            "iosPageName": iosPageName
        ]) { _, new in new }
    }

    private func completeAuthorizationSuccess(_ requestId: Int64, token nextToken: String, sessionId nextSessionId: String?, deviceName nextDeviceName: String?) {
        guard requestId == authorizationRequestId, completedAuthorizationRequestId != requestId else { return }
        completedAuthorizationRequestId = requestId
        token = nextToken
        sessionId = nextSessionId ?? ""
        deviceName = nextDeviceName ?? currentDeviceName()
        let callback = pendingAuthorizationCallback
        pendingAuthorizationCallback = nil
        let payload = authorizationPayload()
        emit("authorization", payload)
        invoke(callback, ok(payload))
    }

    private func completeAuthorizationFailure(_ requestId: Int64, message: String) {
        guard requestId == authorizationRequestId, completedAuthorizationRequestId != requestId else { return }
        completedAuthorizationRequestId = requestId
        let callback = pendingAuthorizationCallback
        pendingAuthorizationCallback = nil
        emit("authorization", stateJson().merging([
            "message": message
        ]) { _, new in new })
        invoke(callback, error(1002, message))
    }

    private func ensureAuthenticated(_ callback: RokidGlassCallback?) -> Bool {
        if client.auth.isAuthenticated() {
            return true
        }
        invoke(callback, error(1002, "Rokid authorization is required"))
        return false
    }

    private func startPhoneAudioEngine(_ options: NSDictionary?) throws -> [String: Any] {
        if phoneAudioStarted {
            _ = stopPhoneAudioEngine(reason: "restart")
        } else if audioStarted {
            client.stopRecord(audioType)
            _ = finalizeAudioStop(reason: "switchToPhoneAudio", sendStop: true, uploadWait: 1.0)
        }
        audioType = stringOption(options, "recordType", stringOption(options, "type", "phone"))
        audioCodecType = 1
        phoneAudioSource = "phone_microphone"
        nativeAudioUploadEnabled = false
        stopNativeAudioUpload(sendStop: false, wait: 1.0)
        guard resetAudioBuffers() else {
            audioCodecType = -1
            throw NSError(domain: "RokidGlassBridge", code: 1011, userInfo: [NSLocalizedDescriptionKey: "Failed to create phone audio file"])
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try? audioSession.setPreferredSampleRate(Double(sampleRate))
        try? audioSession.setPreferredInputNumberOfChannels(channels)
        if let builtInMic = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? audioSession.setPreferredInput(builtInMic)
        }
        try audioSession.setActive(true, options: [])

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: AVAudioChannelCount(channels), interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(domain: "RokidGlassBridge", code: 1012, userInfo: [NSLocalizedDescriptionKey: "Failed to create phone audio converter"])
        }

        phoneAudioEngine = engine
        phoneAudioConverter = converter
        phoneAudioStarted = true
        audioStarted = true
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.handlePhoneAudioBuffer(buffer, inputFormat: inputFormat, outputFormat: outputFormat, timestamp: time.sampleTime)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            phoneAudioEngine = nil
            phoneAudioConverter = nil
            phoneAudioStarted = false
            audioStarted = false
            closePcmFile()
            throw error
        }
        let payload = stateJson().merging([
            "recordType": audioType,
            "audioSource": phoneAudioSource,
            "codec": "pcm",
            "codecType": audioCodecType,
            "audioCodecType": audioCodecType,
            "sampleRate": sampleRate,
            "channels": channels,
            "bitsPerSample": bitsPerSample
        ]) { _, new in new }
        emit("phoneAudioStarted", payload)
        return payload
    }

    private func stopPhoneAudioEngine(reason: String) -> [String: Any] {
        if Thread.isMainThread {
            phoneAudioEngine?.inputNode.removeTap(onBus: 0)
            phoneAudioEngine?.stop()
        } else {
            DispatchQueue.main.sync {
                phoneAudioEngine?.inputNode.removeTap(onBus: 0)
                phoneAudioEngine?.stop()
            }
        }
        phoneAudioEngine = nil
        phoneAudioConverter = nil
        phoneAudioStarted = false
        let data = finalizeAudioStop(reason: reason, sendStop: true, uploadWait: 1.0)
        emit("phoneAudioStopped", data)
        return data
    }

    private func handlePhoneAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, outputFormat: AVAudioFormat, timestamp: AVAudioFramePosition) {
        guard phoneAudioStarted, let converter = phoneAudioConverter else { return }
        let ratio = outputFormat.sampleRate / max(1.0, inputFormat.sampleRate)
        let capacity = max(1, AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 8)
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var provided = false
        var convertError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: converted, error: &convertError, withInputFrom: inputBlock)
        if let convertError = convertError {
            emit("phoneAudioError", stateJson().merging(["message": convertError.localizedDescription]) { _, new in new })
            return
        }
        guard let data = pcmData(from: converted), !data.isEmpty else { return }
        let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
        audioQueue.async { [weak self] in
            self?.handleAudioData(data, timestamp: timestampMs)
        }
    }

    private func pcmData(from buffer: AVAudioPCMBuffer) -> Data? {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let pointer = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { return nil }
        return Data(bytes: pointer, count: Int(audioBuffer.mDataByteSize))
    }

    private func handleAudioData(_ data: Data, timestamp: UInt64) {
        guard audioStarted else { return }
        guard let handle = pcmFileHandle else {
            emit("audioWriteError", stateJson().merging(["message": "PCM file handle is not open"]) { _, new in new })
            return
        }
        handle.write(data)
        audioBytes += data.count
        audioChunkCount += 1

        if nativeAudioUploadEnabled, let uploader = nativeAudioUploader {
            uploader.enqueue(data, session: audioSessionId)
        } else {
            audioRealtimeBuffer.append(data)
            let elapsed = Date().timeIntervalSince(lastAudioEmitAt)
            if audioRealtimeBuffer.count >= realtimeMinBytes || elapsed >= realtimeMaxInterval {
                flushRealtimeAudio(final: false, timestamp: timestamp)
            }
        }
    }

    private func flushRealtimeAudio(final: Bool, timestamp: UInt64 = 0) {
        guard !audioRealtimeBuffer.isEmpty else { return }
        audioRealtimeSeq += 1
        let chunk = audioRealtimeBuffer
        audioRealtimeBuffer.removeAll(keepingCapacity: true)
        lastAudioEmitAt = Date()
        let audioPayload: [String: Any] = [
            "sequence": audioRealtimeSeq,
            "base64": chunk.base64EncodedString(),
            "bytes": chunk.count,
            "final": final,
            "timestamp": timestamp,
            "codec": "pcm",
            "audioSource": phoneAudioStarted ? "phone_microphone" : "rokid_cxr_audio_callback",
            "source": phoneAudioStarted ? "phone_microphone" : "rokid_cxr_audio_callback",
            "audioCodecType": audioCodecType,
            "codecType": audioCodecType,
            "sampleRate": sampleRate,
            "channels": channels,
            "bitsPerSample": bitsPerSample
        ].merging(pcmLevelStats(chunk)) { _, new in new }
        emit("audioChunk", stateJson().merging(audioPayload) { _, new in new })
    }

    private func pcmLevelStats(_ data: Data) -> [String: Any] {
        guard data.count >= 2 else {
            return [
                "sampleCount": 0,
                "avgAbs": 0,
                "maxAbs": 0,
                "nonZeroSamples": 0,
                "silentLike": true
            ]
        }
        var sumAbs = 0
        var maxAbs = 0
        var nonZero = 0
        var index = data.startIndex
        var sampleCount = 0
        while index < data.endIndex {
            let next = data.index(after: index)
            if next >= data.endIndex { break }
            let value = UInt16(data[index]) | (UInt16(data[next]) << 8)
            let sample = Int16(bitPattern: value)
            let absValue = abs(Int(sample))
            sumAbs += absValue
            maxAbs = max(maxAbs, absValue)
            if sample != 0 { nonZero += 1 }
            sampleCount += 1
            index = data.index(after: next)
        }
        return [
            "sampleCount": sampleCount,
            "avgAbs": sampleCount == 0 ? 0 : Double(sumAbs) / Double(sampleCount),
            "maxAbs": maxAbs,
            "nonZeroSamples": nonZero,
            "silentLike": maxAbs <= 2
        ]
    }

    private func resetAudioBuffers() -> Bool {
        closePcmFile()
        audioRealtimeBuffer.removeAll(keepingCapacity: true)
        audioBytes = 0
        audioChunkCount = 0
        audioRealtimeSeq = 0
        audioSessionId += 1
        lastAudioEmitAt = Date.distantPast
        let base = mediaDirectory()
        let timestamp = fileTimestamp()
        pcmPath = base.appendingPathComponent("rokid_\(timestamp).pcm").path
        wavPath = base.appendingPathComponent("rokid_\(timestamp).wav").path
        FileManager.default.createFile(atPath: pcmPath, contents: nil)
        do {
            pcmFileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: pcmPath))
            return true
        } catch {
            pcmFileHandle = nil
            emit("audioWriteError", stateJson().merging(["message": error.localizedDescription]) { _, new in new })
            return false
        }
    }

    private func saveAudioFiles() -> [String: Any] {
        closePcmFile()
        if pcmPath.isEmpty || wavPath.isEmpty {
            return [
                "pcmPath": pcmPath,
                "path": wavPath,
                "bytes": audioBytes,
                "chunkCount": audioChunkCount,
                "durationSeconds": 0
            ]
        }
        do {
            try buildWavFromPcm(pcmPath: pcmPath, wavPath: wavPath, pcmSize: audioBytes)
        } catch {
            emit("audioWriteError", stateJson().merging(["message": error.localizedDescription]) { _, new in new })
        }
        return [
            "pcmPath": pcmPath,
            "path": wavPath,
            "wavPath": wavPath,
            "bytes": audioBytes,
            "chunkCount": audioChunkCount,
            "durationSeconds": Double(audioBytes) / Double(sampleRate * channels * bitsPerSample / 8)
        ]
    }

    private func finalizeAudioStop(reason: String, sendStop: Bool, uploadWait: TimeInterval) -> [String: Any] {
        return audioQueue.sync {
            let stoppedCodecType = audioCodecType
            audioStarted = false
            if nativeAudioUploadEnabled || nativeAudioUploader != nil {
                stopNativeAudioUpload(sendStop: sendStop, wait: uploadWait)
            } else {
                flushRealtimeAudio(final: true)
            }
            let saved = saveAudioFiles()
            emit("audioStateChanged", stateJson())
            audioCodecType = -1
            nativeAudioUploadEnabled = false
            var data = stateJson().merging(saved) { _, new in new }
            data["codecType"] = stoppedCodecType
            data["audioCodecType"] = stoppedCodecType
            data["stopReason"] = reason
            return data
        }
    }

    private func startNativeAudioUpload(_ options: NSDictionary?, session: Int64) {
        stopNativeAudioUpload(sendStop: false, wait: 1.0)
        nativeAudioUploadEnabled = true
        nativeAudioUploadState = "starting"
        nativeAudioUploadError = ""
        nativeAudioEnqueuedBytes = 0
        nativeAudioDroppedBytes = 0
        nativeAudioSentBytes = 0
        nativeAudioSentChunks = 0
        let uploader = RokidNativeAudioUploader(
            options: options,
            session: session,
            defaultChunkBytes: 16000,
            eventHandler: { [weak self] event, message, stats in
                guard let self = self else { return }
                self.audioQueue.async {
                    guard self.audioSessionId == session else { return }
                    self.applyNativeUploadStats(stats)
                    if !message.isEmpty {
                        self.nativeAudioUploadError = message
                    }
                    self.emitNativeUploadEvent(event, message: message)
                }
            },
            messageHandler: { [weak self] message in
                guard let self = self else { return }
                self.audioQueue.async {
                    guard self.audioSessionId == session else { return }
                    self.emit("nativeUploadMessage", self.stateJson().merging(["message": message]) { _, new in new })
                }
            }
        )
        nativeAudioUploader = uploader
        uploader.start()
    }

    private func stopNativeAudioUpload(sendStop: Bool, wait: TimeInterval) {
        let uploader = nativeAudioUploader
        nativeAudioUploader = nil
        uploader?.stop(sendStop: sendStop, wait: wait)
        nativeAudioUploadEnabled = false
        if uploader == nil && nativeAudioUploadState != "idle" {
            nativeAudioUploadState = "stopped"
        }
    }

    private func applyNativeUploadStats(_ stats: RokidNativeAudioUploader.Stats) {
        nativeAudioUploadState = stats.state
        nativeAudioUploadError = stats.error
        nativeAudioEnqueuedBytes = stats.enqueuedBytes
        nativeAudioDroppedBytes = stats.droppedBytes
        nativeAudioSentBytes = stats.sentBytes
        nativeAudioSentChunks = stats.sentChunks
    }

    private func emitNativeUploadEvent(_ event: String, message: String) {
        var payload = stateJson()
        payload["nativeUpload"] = nativeAudioUploadEnabled
        payload["nativeUploadState"] = nativeAudioUploadState
        payload["nativeUploadError"] = message.isEmpty ? nativeAudioUploadError : message
        emit(event, payload)
    }

    private func closePcmFile() {
        guard let handle = pcmFileHandle else { return }
        handle.synchronizeFile()
        handle.closeFile()
        pcmFileHandle = nil
    }

    private func buildWavFromPcm(pcmPath: String, wavPath: String, pcmSize: Int) throws {
        let pcmURL = URL(fileURLWithPath: pcmPath)
        let wavURL = URL(fileURLWithPath: wavPath)
        let wav = try FileHandle(forWritingTo: createEmptyFile(wavURL))
        defer { wav.closeFile() }
        wav.write(wavHeader(dataSize: pcmSize))
        let pcm = try FileHandle(forReadingFrom: pcmURL)
        defer { pcm.closeFile() }
        while true {
            let data = pcm.readData(ofLength: 4096)
            if data.isEmpty { break }
            wav.write(data)
        }
    }

    private func createEmptyFile(_ url: URL) -> URL {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return url
    }

    private func mediaDirectory() -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = root.appendingPathComponent("RokidGlass", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private func wavHeader(dataSize pcmSize: Int) -> Data {
        var header = Data()
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmSize)
        let riffSize = UInt32(36 + pcmSize)

        header.append("RIFF".data(using: .ascii)!)
        appendLE(riffSize, to: &header)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        appendLE(UInt32(16), to: &header)
        appendLE(UInt16(1), to: &header)
        appendLE(UInt16(channels), to: &header)
        appendLE(UInt32(sampleRate), to: &header)
        appendLE(UInt32(byteRate), to: &header)
        appendLE(UInt16(blockAlign), to: &header)
        appendLE(UInt16(bitsPerSample), to: &header)
        header.append("data".data(using: .ascii)!)
        appendLE(dataSize, to: &header)
        return header
    }

    private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private func commandPayload(_ options: NSDictionary?) -> Data {
        let base64 = stringOption(options, "base64", "")
        if !base64.isEmpty, let data = Data(base64Encoded: base64) {
            return data
        }
        let text = stringOption(options, "text", "")
        if !text.isEmpty {
            return text.data(using: .utf8) ?? Data()
        }
        var payload: [String: Any] = [
            "command": stringOption(options, "command", "message"),
            "params": options?["params"] ?? [:]
        ]
        if let raw = options?["payload"] {
            payload["payload"] = raw
        }
        return (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()
    }

    private func defaultCustomViewJson(title: String, text: String) -> String {
        let root: [String: Any] = [
            "type": "LinearLayout",
            "props": [
                "layout_width": "match_parent",
                "layout_height": "match_parent",
                "orientation": "vertical",
                "gravity": "center_vertical",
                "paddingTop": "140dp",
                "paddingBottom": "100dp"
            ],
            "children": [
                [
                    "type": "TextView",
                    "props": [
                        "id": "tv_title",
                        "layout_width": "wrap_content",
                        "layout_height": "wrap_content",
                        "text": title,
                        "textColor": "#FF00FF00",
                        "textSize": "16sp",
                        "textStyle": "bold",
                        "marginBottom": "20dp",
                        "paddingStart": "16dp",
                        "paddingEnd": "16dp"
                    ]
                ],
                [
                    "type": "TextView",
                    "props": [
                        "id": "textView",
                        "layout_width": "wrap_content",
                        "layout_height": "wrap_content",
                        "text": text,
                        "textColor": "#FF00FF00",
                        "textSize": "16sp",
                        "gravity": "center",
                        "paddingStart": "16dp",
                        "paddingEnd": "16dp"
                    ]
                ]
            ]
        ]
        return jsonString(root)
    }

    private func defaultUpdateJson(text: String) -> String {
        return jsonString([
            [
                "action": "update",
                "id": "textView",
                "props": ["text": text]
            ]
        ])
    }

    private func openCustomViewVariant(
        requestId: Int64,
        variants: [(name: String, json: String)],
        index: Int,
        callback: RokidGlassCallback?,
        attemptTimeoutMs: Int
    ) {
        guard requestId == customViewOpenRequestId else { return }
        guard index < variants.count else {
            sceneReady = false
            lastCustomViewStage = "failed"
            lastCustomViewErrorCode = 1003
            lastCustomViewMessage = "openCustomView failed after \(variants.count) variants"
            let payload = customViewPayload(extra: [
                "success": false,
                "variantCount": variants.count
            ])
            emit("customViewError", payload)
            invoke(callback, error(1003, lastCustomViewMessage))
            return
        }

        let variant = variants[index]
        sceneReady = false
        lastCustomViewStage = "opening"
        lastCustomViewVariant = variant.name
        lastCustomViewErrorCode = -1
        lastCustomViewMessage = ""
        lastCustomViewJson = variant.json
        lastCustomViewJsonBytes = variant.json.data(using: .utf8)?.count ?? 0
        emit("customViewOpenAttempt", customViewPayload(extra: [
            "success": false,
            "variantIndex": index,
            "variantCount": variants.count
        ]))

        var completed = false
        let finish: (_ success: Bool, _ errorCode: Int?, _ timedOut: Bool) -> Void = { [weak self] success, errorCode, timedOut in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard requestId == self.customViewOpenRequestId, !completed else { return }
                completed = true
                self.sceneReady = success
                if success {
                    self.lastCustomViewStage = "opened"
                    self.lastCustomViewErrorCode = -1
                    self.lastCustomViewMessage = ""
                    let payload = self.customViewPayload(extra: [
                        "success": true,
                        "variantIndex": index,
                        "variantCount": variants.count
                    ])
                    self.emit("customViewOpened", payload)
                    self.invoke(callback, self.ok(payload))
                    return
                }

                self.lastCustomViewStage = timedOut ? "timeout" : "failed"
                self.lastCustomViewErrorCode = timedOut ? 1004 : (errorCode ?? 1003)
                self.lastCustomViewMessage = timedOut
                    ? "openCustomView timeout: \(variant.name), timeoutMs=\(attemptTimeoutMs)"
                    : "openCustomView failed: \(variant.name), errorCode=\(String(describing: errorCode))"
                self.emit(timedOut ? "customViewOpenTimeout" : "customViewOpenFailed", self.customViewPayload(extra: [
                    "success": false,
                    "errorCode": timedOut ? 1004 : (errorCode ?? -1),
                    "variantIndex": index,
                    "variantCount": variants.count,
                    "timeoutMs": timedOut ? attemptTimeoutMs : 0
                ]))

                if index + 1 < variants.count {
                    self.lastCustomViewStage = "retryWaiting"
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
                        self?.openCustomViewVariant(
                            requestId: requestId,
                            variants: variants,
                            index: index + 1,
                            callback: callback,
                            attemptTimeoutMs: attemptTimeoutMs
                        )
                    }
                    return
                }

                let message = timedOut
                    ? "openCustomView timeout after \(variants.count) variants, timeoutMs=\(attemptTimeoutMs)"
                    : "openCustomView failed after \(variants.count) variants, lastErrorCode=\(String(describing: errorCode))"
                self.lastCustomViewMessage = message
                let payload = self.customViewPayload(extra: [
                    "success": false,
                    "errorCode": timedOut ? 1004 : (errorCode ?? -1),
                    "variantIndex": index,
                    "variantCount": variants.count,
                    "timeoutMs": timedOut ? attemptTimeoutMs : 0
                ])
                self.emit("customViewError", payload)
                self.invoke(callback, self.error(1003, message))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(attemptTimeoutMs)) {
            finish(false, 1004, true)
        }
        client.openCustomView(variant.json) { success, errorCode in
            finish(success, errorCode, false)
        }
    }

    private func customViewOpenVariants(
        options: NSDictionary?,
        requestedViewJson: String,
        title: String,
        text: String
    ) -> [(name: String, json: String)] {
        var variants: [(name: String, json: String)] = []
        if boolOption(options, "preferMinimalCustomView", false) {
            appendCustomViewVariant(&variants, name: "compact", json: compactCustomViewJson(title: title, text: text))
            appendCustomViewVariant(&variants, name: "textOnly", json: textOnlyCustomViewJson(text: text))
        }
        appendCustomViewVariant(&variants, name: "officialSampleIcon", json: officialSampleIconCustomViewJson(title: title, text: text))
        appendCustomViewVariant(&variants, name: "requested", json: requestedViewJson)
        appendCustomViewVariant(&variants, name: "officialSampleText", json: officialSampleTextCustomViewJson(title: title, text: text))
        appendCustomViewVariant(&variants, name: "nativeDefault", json: defaultCustomViewJson(title: title, text: text))
        appendCustomViewVariant(&variants, name: "compact", json: compactCustomViewJson(title: title, text: text))
        appendCustomViewVariant(&variants, name: "textOnly", json: textOnlyCustomViewJson(text: text))
        return variants
    }

    private func appendCustomViewVariant(
        _ variants: inout [(name: String, json: String)],
        name: String,
        json: String
    ) {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !variants.contains(where: { $0.json == trimmed }) else { return }
        variants.append((name: name, json: trimmed))
    }

    private func uploadDefaultCustomViewIconsIfNeeded(_ options: NSDictionary?, completion: @escaping () -> Void) {
        guard boolOption(options, "uploadDefaultIcon", true) else {
            completion()
            return
        }
        let iconsJson = jsonString([
            [
                "name": "icon_0",
                "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
            ]
        ])
        client.sendCustomViewIcons(iconsJson) { [weak self] success in
            DispatchQueue.main.async {
                self?.emit("customViewIconsUploaded", self?.customViewPayload(extra: [
                    "success": success
                ]) ?? [:])
                completion()
            }
        }
    }

    private func compactCustomViewJson(title: String, text: String) -> String {
        return jsonString([
            "type": "LinearLayout",
            "props": [
                "layout_width": "match_parent",
                "layout_height": "match_parent",
                "orientation": "vertical",
                "gravity": "center_vertical",
                "paddingTop": "140dp",
                "paddingBottom": "100dp"
            ],
            "children": [
                [
                    "type": "TextView",
                    "props": [
                        "id": "titleView",
                        "layout_width": "wrap_content",
                        "layout_height": "wrap_content",
                        "text": title,
                        "textColor": "#FF00FF00",
                        "textSize": "16sp",
                        "textStyle": "bold",
                        "marginBottom": "20dp"
                    ]
                ],
                [
                    "type": "TextView",
                    "props": [
                        "id": "textView",
                        "layout_width": "wrap_content",
                        "layout_height": "wrap_content",
                        "text": text,
                        "textColor": "#FF00FF00",
                        "textSize": "16sp",
                        "gravity": "center"
                    ]
                ]
            ]
        ])
    }

    private func officialSampleTextCustomViewJson(title: String, text: String) -> String {
        return jsonString([
            "type": "LinearLayout",
            "props": [
                "layout_width": "match_parent",
                "layout_height": "match_parent",
                "orientation": "vertical",
                "gravity": "center_vertical",
                "paddingTop": "140dp",
                "paddingBottom": "100dp",
                "backgroundColor": "#FF000000"
            ],
            "children": [
                [
                    "type": "TextView",
                    "props": [
                        "id": "tv_title",
                        "layout_width": "wrap_content",
                        "layout_height": "wrap_content",
                        "text": title,
                        "textColor": "#FF00FF00",
                        "textSize": "16sp",
                        "textStyle": "bold",
                        "marginBottom": "20dp"
                    ]
                ],
                [
                    "type": "RelativeLayout",
                    "props": [
                        "layout_width": "match_parent",
                        "layout_height": "100dp",
                        "paddingStart": "10dp",
                        "backgroundColor": "#000000"
                    ],
                    "children": [
                        [
                            "type": "TextView",
                            "props": [
                                "id": "textView",
                                "layout_width": "wrap_content",
                                "layout_height": "wrap_content",
                                "text": text,
                                "textColor": "#FF00FF00",
                                "textSize": "16sp",
                                "layout_centerVertical": "true"
                            ]
                        ]
                    ]
                ]
            ]
        ])
    }

    private func officialSampleIconCustomViewJson(title: String, text: String) -> String {
        return jsonString([
            "type": "LinearLayout",
            "props": [
                "layout_width": "match_parent",
                "layout_height": "match_parent",
                "orientation": "vertical",
                "gravity": "center_vertical",
                "paddingTop": "140dp",
                "paddingBottom": "100dp",
                "backgroundColor": "#FF000000"
            ],
            "children": [
                [
                    "type": "TextView",
                    "props": [
                        "id": "tv_title",
                        "layout_width": "wrap_content",
                        "layout_height": "wrap_content",
                        "text": title,
                        "textColor": "#FF00FF00",
                        "textSize": "16sp",
                        "textStyle": "bold",
                        "marginBottom": "20dp"
                    ]
                ],
                [
                    "type": "RelativeLayout",
                    "props": [
                        "layout_width": "match_parent",
                        "layout_height": "100dp",
                        "paddingStart": "10dp",
                        "backgroundColor": "#000000"
                    ],
                    "children": [
                        [
                            "type": "ImageView",
                            "props": [
                                "id": "iv_icon",
                                "layout_width": "60dp",
                                "layout_height": "60dp",
                                "name": "icon_0",
                                "layout_alignParentStart": "true",
                                "layout_centerVertical": "true"
                            ]
                        ],
                        [
                            "type": "TextView",
                            "props": [
                                "id": "textView",
                                "layout_width": "wrap_content",
                                "layout_height": "wrap_content",
                                "text": text,
                                "textColor": "#FF00FF00",
                                "textSize": "16sp",
                                "marginStart": "15dp",
                                "layout_toEndOf": "iv_icon",
                                "layout_centerVertical": "true"
                            ]
                        ]
                    ]
                ]
            ]
        ])
    }

    private func textOnlyCustomViewJson(text: String) -> String {
        return jsonString([
            "type": "LinearLayout",
            "props": [
                "layout_width": "match_parent",
                "layout_height": "match_parent",
                "orientation": "vertical",
                "gravity": "center_vertical",
                "paddingTop": "140dp",
                "paddingBottom": "100dp"
            ],
            "children": [
                [
                    "type": "TextView",
                    "props": [
                        "id": "textView",
                        "layout_width": "wrap_content",
                        "layout_height": "wrap_content",
                        "text": text,
                        "textColor": "#FF00FF00",
                        "textSize": "16sp",
                        "gravity": "center",
                        "paddingStart": "16dp",
                        "paddingEnd": "16dp"
                    ]
                ]
            ]
        ])
    }

    private func customViewPayload(extra: [String: Any] = [:]) -> [String: Any] {
        var payload = stateJson()
        payload["customViewStage"] = lastCustomViewStage
        payload["customViewVariant"] = lastCustomViewVariant
        payload["customViewErrorCode"] = lastCustomViewErrorCode
        payload["customViewMessage"] = lastCustomViewMessage
        payload["customViewJsonBytes"] = lastCustomViewJsonBytes
        payload["iosInitialized"] = Self.initialized
        payload["iosInitializedSessionType"] = Self.initializedSessionType
        payload["rokidAIAppInstalled"] = client.isRokidAppInstalled()
        payload["bleConnected"] = RGCxrClientBLE.shared.isConnected
        payload["connectedDeviceName"] = RGCxrClientBLE.shared.connectedDeviceName ?? ""
        for (key, value) in extra {
            payload[key] = value
        }
        return payload
    }

    private func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private func stringOption(_ options: NSDictionary?, _ key: String, _ defaultValue: String) -> String {
        guard let value = options?[key] else { return defaultValue }
        if let string = value as? String { return string }
        return "\(value)"
    }

    private func intOption(_ options: NSDictionary?, _ key: String, _ defaultValue: Int) -> Int {
        guard let value = options?[key] else { return defaultValue }
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let int = Int(string) { return int }
        return defaultValue
    }

    private func boolOption(_ options: NSDictionary?, _ key: String, _ defaultValue: Bool) -> Bool {
        guard let value = options?[key] else { return defaultValue }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            let lower = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "y"].contains(lower) { return true }
            if ["false", "0", "no", "n"].contains(lower) { return false }
        }
        return defaultValue
    }

    private func stringArrayOption(_ options: NSDictionary?, _ key: String, _ defaultValue: [String]) -> [String] {
        guard let value = options?[key] else { return defaultValue }
        if let array = value as? [String] {
            return array.filter { !$0.isEmpty }
        }
        if let array = value as? NSArray {
            let mapped = array.compactMap { item -> String? in
                if let string = item as? String, !string.isEmpty { return string }
                return nil
            }
            return mapped.isEmpty ? defaultValue : mapped
        }
        if let string = value as? String {
            let mapped = string.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return mapped.isEmpty ? defaultValue : mapped
        }
        return defaultValue
    }

    private func stateJson() -> [String: Any] {
        let currentSessionId = sessionId.isEmpty ? (client.auth.currentSessionId ?? "") : sessionId
        let authenticated = client.auth.isAuthenticated() || !token.isEmpty
        let currentName = currentDeviceName()
        let glassId = currentGlassId()
        return [
            "sessionType": sessionType,
            "packageName": packageName,
            "hasToken": authenticated,
            "ready": authenticated,
            "cxrConnected": authenticated,
            "authSessionMissing": authenticated && currentSessionId.isEmpty,
            "glassBtConnected": RGCxrClientBLE.shared.isConnected,
            "sceneReady": sceneReady,
            "audioStarted": audioStarted,
            "phoneAudioStarted": phoneAudioStarted,
            "audioSource": phoneAudioStarted ? "phone_microphone" : phoneAudioSource,
            "audioCodecType": audioCodecType,
            "codecType": audioCodecType,
            "audioSceneId": audioSceneId,
            "audioSessionId": audioSessionId,
            "audioChunkCount": audioChunkCount,
            "pcmPath": pcmPath,
            "path": wavPath,
            "bridgeVersion": bridgeVersion,
            "iosInitialized": Self.initialized,
            "iosInitializedSessionType": Self.initializedSessionType,
            "iosBundleId": iosBundleId,
            "iosPageName": iosPageName,
            "appDisplayName": appDisplayName,
            "customViewStage": lastCustomViewStage,
            "customViewVariant": lastCustomViewVariant,
            "customViewErrorCode": lastCustomViewErrorCode,
            "customViewMessage": lastCustomViewMessage,
            "customViewJsonBytes": lastCustomViewJsonBytes,
            "nativeUpload": nativeAudioUploadEnabled,
            "nativeUploadState": nativeAudioUploadState,
            "nativeUploadError": nativeAudioUploadError,
            "nativeUploadEnqueuedBytes": nativeAudioEnqueuedBytes,
            "nativeUploadDroppedBytes": nativeAudioDroppedBytes,
            "nativeUploadSentBytes": nativeAudioSentBytes,
            "nativeUploadSentChunks": nativeAudioSentChunks,
            "glassId": glassId,
            "glassIdSource": glassId.isEmpty ? "unavailable" : "connectedDeviceName",
            "glassIdStable": false,
            "deviceId": glassId,
            "sn": "",
            "deviceName": currentName,
            "bleConnected": RGCxrClientBLE.shared.isConnected,
            "connectedDeviceName": RGCxrClientBLE.shared.connectedDeviceName ?? "",
            "sessionId": currentSessionId,
            "glassDeviceInfo": [
                "glassId": glassId,
                "glassIdSource": glassId.isEmpty ? "unavailable" : "connectedDeviceName",
                "glassIdStable": false,
                "deviceId": glassId,
                "sn": "",
                "deviceName": currentName,
                "sessionId": currentSessionId
            ]
        ]
    }

    private func currentDeviceName() -> String {
        if let name = client.auth.currentDeviceName, !name.isEmpty {
            return name
        }
        if let name = RGCxrClientBLE.shared.connectedDeviceName, !name.isEmpty {
            return name
        }
        return deviceName
    }

    private func currentGlassId() -> String {
        if let name = RGCxrClientBLE.shared.connectedDeviceName, !name.isEmpty {
            return name
        }
        return ""
    }

    private func audioSceneOption(_ options: NSDictionary?, defaultValue: RGCxrAudioSceneId) -> RGCxrAudioSceneId {
        let sceneName = stringOption(options, "audioScene", "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch sceneName {
        case "interaction", "interact", "default":
            return .interaction
        case "translation", "translate":
            return .translation
        case "call":
            return .call
        case "conference", "meeting", "full", "all", "both":
            return .conference
        default:
            break
        }
        let raw = intOption(options, "audioSceneId", -1)
        if let scene = RGCxrAudioSceneId(rawValue: raw) {
            return scene
        }
        return defaultValue
    }

    private func audioSceneName(_ scene: RGCxrAudioSceneId) -> String {
        switch scene {
        case .interaction:
            return "interaction"
        case .translation:
            return "translation"
        case .call:
            return "call"
        case .conference:
            return "conference"
        @unknown default:
            return "unknown"
        }
    }

    private func ok(_ data: [String: Any]) -> [String: Any] {
        return ["code": 0, "data": data]
    }

    private func error(_ code: Int, _ message: String) -> [String: Any] {
        return ["code": code, "message": message]
    }

    private func invoke(_ callback: RokidGlassCallback?, _ result: [String: Any]) {
        DispatchQueue.main.async {
            callback?(result, false)
        }
    }

    private func invokeKeepAlive(_ callback: RokidGlassCallback?, _ result: [String: Any]) {
        DispatchQueue.main.async {
            callback?(result, true)
        }
    }

    private func emit(_ event: String, _ data: [String: Any]) {
        var payload = data
        payload["event"] = event
        invokeKeepAlive(eventCallback, ok(payload))
    }
}

private final class RokidNativeAudioUploader: NSObject {
    struct Stats {
        var state: String
        var error: String
        var enqueuedBytes: Int
        var droppedBytes: Int
        var sentBytes: Int
        var sentChunks: Int
    }

    private let condition = NSCondition()
    private var queue: [Data] = []
    private var queueBytes = 0
    private let wsUrl: String
    private let headers: [String: String]
    private let sessionData: [String: Any]
    private let startPayload: [String: Any]
    private let stopPayload: [String: Any]
    private let chunkBytes: Int
    private let maxQueueBytes: Int
    private let session: Int64
    private let eventHandler: (String, String, Stats) -> Void
    private let messageHandler: (String) -> Void
    private var pending = Data()
    private var thread: Thread?
    private var urlSession: URLSession?
    private var socketTask: URLSessionWebSocketTask?
    private var stoppedSemaphore = DispatchSemaphore(value: 0)
    private var running = true
    private var sendStopOnClose = false
    private var state = "idle"
    private var errorMessage = ""
    private var enqueuedBytes = 0
    private var droppedBytes = 0
    private var sentBytes = 0
    private var sentChunks = 0

    init(
        options: NSDictionary?,
        session: Int64,
        defaultChunkBytes: Int,
        eventHandler: @escaping (String, String, Stats) -> Void,
        messageHandler: @escaping (String) -> Void
    ) {
        self.session = session
        self.eventHandler = eventHandler
        self.messageHandler = messageHandler
        self.wsUrl = RokidNativeAudioUploader.absoluteWsUrl(RokidNativeAudioUploader.stringOption(options, "wsUrl", ""))
        self.headers = RokidNativeAudioUploader.stringDictionaryOption(options, "headers")
        self.sessionData = RokidNativeAudioUploader.dictionaryOption(options, "sessionData")
        self.chunkBytes = max(640, RokidNativeAudioUploader.intOption(options, "chunkBytes", defaultChunkBytes))
        let queueChunks = max(60, RokidNativeAudioUploader.intOption(options, "maxQueueChunks", 240))
        self.maxQueueBytes = max(self.chunkBytes * 10, self.chunkBytes * queueChunks)
        let providedStart = RokidNativeAudioUploader.dictionaryOption(options, "startPayload")
        let providedStop = RokidNativeAudioUploader.dictionaryOption(options, "stopPayload")
        self.startPayload = providedStart.isEmpty
            ? RokidNativeAudioUploader.defaultPayload(event: "session.start", sessionData: self.sessionData, session: session, audio: nil, index: 0, bytes: 0, final: false, chunkBytes: self.chunkBytes)
            : providedStart
        self.stopPayload = providedStop.isEmpty
            ? RokidNativeAudioUploader.defaultPayload(event: "session.stop", sessionData: self.sessionData, session: session, audio: nil, index: 0, bytes: 0, final: true, chunkBytes: self.chunkBytes)
            : providedStop
        super.init()
    }

    func start() {
        let next = Thread { [weak self] in
            self?.runLoop()
        }
        next.name = "RokidGlassNativeUpload"
        thread = next
        next.start()
    }

    func enqueue(_ data: Data, session nextSession: Int64) {
        guard !data.isEmpty, nextSession == session else { return }
        condition.lock()
        defer {
            condition.signal()
            condition.unlock()
        }
        guard running else { return }
        queue.append(data)
        queueBytes += data.count
        enqueuedBytes += data.count
        while queueBytes > maxQueueBytes, !queue.isEmpty {
            let dropped = queue.removeFirst()
            queueBytes -= dropped.count
            droppedBytes += dropped.count
        }
    }

    func stop(sendStop: Bool, wait: TimeInterval) {
        condition.lock()
        sendStopOnClose = sendStop
        running = false
        condition.signal()
        condition.unlock()
        _ = stoppedSemaphore.wait(timeout: .now() + max(0.1, wait))
        socketTask?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
    }

    private func runLoop() {
        do {
            state = "connecting"
            try connect()
            state = "connected"
            receiveLoop()
            try sendJSON(startPayload)
            emit("nativeUploadStarted")
            var lastStatsAt = Date.distantPast
            while true {
                if let next = pollQueue(wait: running ? 0.25 : 0.0) {
                    pending.append(next)
                }
                try flushUploadChunks(final: false)
                if Date().timeIntervalSince(lastStatsAt) >= 1.0 {
                    lastStatsAt = Date()
                    emit("nativeUploadStats")
                }
                if !running && queue.isEmpty && pending.isEmpty {
                    break
                }
            }
            try flushUploadChunks(final: true)
            if sendStopOnClose {
                try sendJSON(stopPayload)
            }
            state = "stopped"
            emit("nativeUploadStopped")
        } catch {
            state = "error"
            errorMessage = error.localizedDescription
            emit("nativeUploadError", message: errorMessage)
        }
        socketTask?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        condition.lock()
        queue.removeAll()
        queueBytes = 0
        condition.unlock()
        stoppedSemaphore.signal()
    }

    private func connect() throws {
        guard let url = URL(string: wsUrl), let scheme = url.scheme, ["ws", "wss"].contains(scheme.lowercased()) else {
            throw NSError(domain: "RokidNativeAudioUploader", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Unsupported websocket url: \(wsUrl)"])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let session = URLSession(configuration: .default)
        urlSession = session
        socketTask = session.webSocketTask(with: request)
        socketTask?.resume()
    }

    private func receiveLoop() {
        socketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if !text.isEmpty {
                        self.messageHandler(text)
                    }
                case .data(let data):
                    if !data.isEmpty {
                        self.messageHandler(data.base64EncodedString())
                    }
                @unknown default:
                    break
                }
                if self.running {
                    self.receiveLoop()
                }
            case .failure(let error):
                if self.running {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func pollQueue(wait: TimeInterval) -> Data? {
        condition.lock()
        defer { condition.unlock() }
        if queue.isEmpty, wait > 0, running {
            condition.wait(until: Date().addingTimeInterval(wait))
        }
        guard !queue.isEmpty else { return nil }
        let data = queue.removeFirst()
        queueBytes -= data.count
        return data
    }

    private func flushUploadChunks(final: Bool) throws {
        guard !pending.isEmpty else { return }
        if !final, pending.count < chunkBytes { return }
        var offset = 0
        while pending.count - offset >= chunkBytes {
            let chunk = pending.subdata(in: offset..<(offset + chunkBytes))
            try sendAudioChunk(chunk, final: false)
            offset += chunkBytes
        }
        let remaining = pending.count - offset
        if remaining <= 0 {
            pending.removeAll(keepingCapacity: true)
            return
        }
        let tail = pending.subdata(in: offset..<pending.count)
        pending.removeAll(keepingCapacity: true)
        if final {
            try sendAudioChunk(tail, final: true)
        } else {
            pending.append(tail)
        }
    }

    private func sendAudioChunk(_ data: Data, final: Bool) throws {
        guard !data.isEmpty else { return }
        let index = sentChunks + 1
        let payload = RokidNativeAudioUploader.defaultPayload(
            event: "audio.chunk",
            sessionData: sessionData,
            session: session,
            audio: data,
            index: index,
            bytes: data.count,
            final: final,
            chunkBytes: chunkBytes
        )
        try sendJSON(payload)
        sentChunks = index
        sentBytes += data.count
    }

    private func sendJSON(_ payload: [String: Any]) throws {
        guard let socketTask = socketTask else {
            throw NSError(domain: "RokidNativeAudioUploader", code: 1002, userInfo: [NSLocalizedDescriptionKey: "WebSocket is not connected"])
        }
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw NSError(domain: "RokidNativeAudioUploader", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Invalid websocket payload"])
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let text = String(data: data, encoding: .utf8) ?? "{}"
        let semaphore = DispatchSemaphore(value: 0)
        var sendError: Error?
        socketTask.send(.string(text)) { error in
            sendError = error
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            throw NSError(domain: "RokidNativeAudioUploader", code: 1004, userInfo: [NSLocalizedDescriptionKey: "WebSocket send timed out"])
        }
        if let sendError = sendError {
            throw sendError
        }
    }

    private func emit(_ event: String, message: String = "") {
        eventHandler(event, message, snapshot())
    }

    private func snapshot() -> Stats {
        return Stats(
            state: state,
            error: errorMessage,
            enqueuedBytes: enqueuedBytes,
            droppedBytes: droppedBytes,
            sentBytes: sentBytes,
            sentChunks: sentChunks
        )
    }

    private static func defaultPayload(event: String, sessionData: [String: Any], session: Int64, audio: Data?, index: Int, bytes: Int, final: Bool, chunkBytes: Int) -> [String: Any] {
        var data = sessionData
        data["type"] = event
        data["messageType"] = event
        data["audioTransport"] = "websocket-json-base64"
        data["transport"] = "json"
        data["codec"] = "pcm"
        data["format"] = "pcm_s16le"
        data["mimeType"] = "audio/pcm"
        data["sampleRate"] = 16000
        data["channels"] = 1
        data["bitsPerSample"] = 16
        data["endian"] = "little"
        data["timestamp"] = Int64(Date().timeIntervalSince1970 * 1000)
        data["audioSessionId"] = session
        data["nativeUpload"] = true
        data["chunkBytes"] = bytes > 0 ? bytes : chunkBytes
        data["chunkDurationMs"] = bytes > 0 ? Int(round(Double(bytes) / 2.0 / 16000.0 * 1000.0)) : 0
        if event == "audio.chunk", let audio = audio {
            let stats = pcmLevelStats(audio)
            data["chunkIndex"] = index
            data["chunkSeq"] = index
            data["bytes"] = bytes
            data["final"] = final
            data["chunkBase64"] = audio.base64EncodedString()
            data["pcmAvgAbs"] = stats.avgAbs
            data["pcmMaxAbs"] = stats.maxAbs
            data["pcmNonZeroSamples"] = stats.nonZeroSamples
            data["pcmNonZeroBytes"] = stats.nonZeroBytes
            data["pcmSilentLike"] = stats.maxAbs <= 2
            data["pcmFirstBytesHex"] = stats.firstBytesHex
            data["pcmGain"] = 1
        }
        return ["event": event, "data": data]
    }

    private struct PcmStats {
        let sampleCount: Int
        let avgAbs: Double
        let maxAbs: Int
        let nonZeroSamples: Int
        let nonZeroBytes: Int
        let firstBytesHex: String
    }

    private static func pcmLevelStats(_ data: Data) -> PcmStats {
        guard data.count >= 2 else {
            return PcmStats(sampleCount: 0, avgAbs: 0, maxAbs: 0, nonZeroSamples: 0, nonZeroBytes: 0, firstBytesHex: "")
        }
        var sumAbs = 0
        var maxAbs = 0
        var nonZeroSamples = 0
        var nonZeroBytes = 0
        for byte in data where byte != 0 {
            nonZeroBytes += 1
        }
        var index = data.startIndex
        var sampleCount = 0
        while index < data.endIndex {
            let next = data.index(after: index)
            if next >= data.endIndex { break }
            let value = UInt16(data[index]) | (UInt16(data[next]) << 8)
            let sample = Int16(bitPattern: value)
            let absValue = abs(Int(sample))
            sumAbs += absValue
            maxAbs = max(maxAbs, absValue)
            if sample != 0 { nonZeroSamples += 1 }
            sampleCount += 1
            index = data.index(after: next)
        }
        let firstBytes = data.prefix(8).map { String(format: "%02x", Int($0)) }.joined()
        return PcmStats(
            sampleCount: sampleCount,
            avgAbs: sampleCount == 0 ? 0 : Double(sumAbs) / Double(sampleCount),
            maxAbs: maxAbs,
            nonZeroSamples: nonZeroSamples,
            nonZeroBytes: nonZeroBytes,
            firstBytesHex: firstBytes
        )
    }

    private static func absoluteWsUrl(_ url: String) -> String {
        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("ws://") || value.hasPrefix("wss://") { return value }
        if value.hasPrefix("http://") { return "ws://" + String(value.dropFirst("http://".count)) }
        if value.hasPrefix("https://") { return "wss://" + String(value.dropFirst("https://".count)) }
        return value
    }

    private static func dictionaryOption(_ options: NSDictionary?, _ key: String) -> [String: Any] {
        guard let value = options?[key] else { return [:] }
        if let dict = value as? [String: Any] { return dict }
        if let dict = value as? NSDictionary { return dict as? [String: Any] ?? [:] }
        return [:]
    }

    private static func stringDictionaryOption(_ options: NSDictionary?, _ key: String) -> [String: String] {
        let raw = dictionaryOption(options, key)
        var result: [String: String] = [:]
        for (key, value) in raw {
            result[key] = "\(value)"
        }
        return result
    }

    private static func stringOption(_ options: NSDictionary?, _ key: String, _ defaultValue: String) -> String {
        guard let value = options?[key] else { return defaultValue }
        if let string = value as? String { return string }
        return "\(value)"
    }

    private static func intOption(_ options: NSDictionary?, _ key: String, _ defaultValue: Int) -> Int {
        guard let value = options?[key] else { return defaultValue }
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let int = Int(string) { return int }
        return defaultValue
    }
}
