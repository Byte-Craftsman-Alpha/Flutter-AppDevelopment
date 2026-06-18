import Flutter
import UIKit
import UserNotifications // Added explicitly for safety

@main
@objc class AppDelegate: FlutterAppDelegate { // Cleaned up implicit delegate signature
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 💡 CRITICAL: Configure the notification presentation layer right at startup
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}