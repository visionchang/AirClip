import UIKit
import UserNotifications

final class AirClipAppDelegate_iOS: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // 推送功能已移除：不再请求通知授权或注册远程通知

        return true
    }

    // 推送相关回调已移除
}
