import Flutter
import UIKit

public class FirebaseMessagingHandlerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "firebase_messaging_handler",
      binaryMessenger: registrar.messenger()
    )
    let instance = FirebaseMessagingHandlerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isBadgeSupported":
      result(true)
    case "setBadgeCount":
      guard
        let arguments = call.arguments as? [String: Any],
        let count = arguments["count"] as? Int,
        count >= 0
      else {
        result(FlutterError(
          code: "invalid-badge-count",
          message: "Badge count must be a non-negative integer.",
          details: nil
        ))
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.applicationIconBadgeNumber = count
        result(true)
      }
    case "getBadgeCount":
      DispatchQueue.main.async {
        result(UIApplication.shared.applicationIconBadgeNumber)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
