import Foundation
import UIKit

@objc(UniPluginProtocol)
public protocol UniPluginProtocol: NSObjectProtocol {}

@objc(RokidGlassPluginProxy)
@objcMembers
public class RokidGlassPluginProxy: NSObject, UniPluginProtocol {
    public func onCreateUniPlugin() {
        RokidGlassBridge.bootstrapDefault()
    }

    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        RokidGlassBridge.bootstrapDefault()
        return true
    }

    public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return RokidGlassBridge.handleOpenURL(url)
    }

    public func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        return RokidGlassBridge.handleOpenURL(url)
    }

    public func application(_ application: UIApplication, handleOpen url: URL) -> Bool {
        return RokidGlassBridge.handleOpenURL(url)
    }

    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else {
            return false
        }
        return RokidGlassBridge.handleOpenURL(url)
    }

    @available(iOS 13.0, *)
    public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            if RokidGlassBridge.handleOpenURL(context.url) {
                return
            }
        }
    }

    @available(iOS 13.0, *)
    public func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else {
            return
        }
        _ = RokidGlassBridge.handleOpenURL(url)
    }
}

@objc(RokidCXRLPluginProxy)
@objcMembers
public final class RokidCXRLPluginProxy: RokidGlassPluginProxy {}
