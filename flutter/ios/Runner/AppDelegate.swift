import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The key comes from Flutter/Secrets.xcconfig (gitignored) via the
    // GOOGLE_MAPS_API_KEY entry in Info.plist. Without it the app still
    // starts; the embedded map just can't load tiles.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String,
      !key.isEmpty
    {
      GMSServices.provideAPIKey(key)
    } else {
      NSLog("Google Maps API key is not configured (Flutter/Secrets.xcconfig)")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
