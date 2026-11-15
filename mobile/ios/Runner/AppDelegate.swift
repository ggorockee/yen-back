import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets flutter_local_notifications present reminders while the app is open.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReceiptOcr") {
      ReceiptOcr.register(messenger: registrar.messenger())
    }
  }
}

/// On-device receipt text recognition with Apple Vision. Photos never leave
/// the device. Japanese recognition needs iOS 16 (request revision 3); older
/// versions fall back to Latin text (digits, ¥, dates still read).
enum ReceiptOcr {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "yenback/receipt_ocr", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let image = UIImage(contentsOfFile: path),
            let cgImage = image.cgImage
      else {
        result(FlutterError(code: "BAD_IMAGE", message: "cannot read image", details: nil))
        return
      }
      let orientation = CGImagePropertyOrientation(image.imageOrientation)
      DispatchQueue.global(qos: .userInitiated).async {
        let lines = recognize(cgImage: cgImage, orientation: orientation)
        DispatchQueue.main.async { result(lines) }
      }
    }
  }

  /// Returns [{text, left, top, width, height}] normalized to 0..1 with a
  /// top-left origin (Vision uses bottom-left).
  static func recognize(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> [[String: Any]] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    // Language correction "fixes" prices and product codes into words.
    request.usesLanguageCorrection = false
    if #available(iOS 16.0, *) {
      request.revision = VNRecognizeTextRequestRevision3
      request.recognitionLanguages = ["ja-JP", "en-US"]
    }
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }
    return (request.results ?? []).compactMap { observation in
      guard let text = observation.topCandidates(1).first?.string else { return nil }
      let box = observation.boundingBox
      return [
        "text": text,
        "left": box.minX,
        "top": 1 - box.maxY,
        "width": box.width,
        "height": box.height,
      ]
    }
  }
}

extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .down: self = .down
    case .left: self = .left
    case .right: self = .right
    case .upMirrored: self = .upMirrored
    case .downMirrored: self = .downMirrored
    case .leftMirrored: self = .leftMirrored
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
