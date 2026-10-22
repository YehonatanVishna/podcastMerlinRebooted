import Cocoa
import FlutterMacOS
import CoreWLAN
import Network
import AVFoundation

extension AVPlayerItem {
  @objc func merlin_setAudioTimePitchAlgorithm(_ algorithm: AVAudioTimePitchAlgorithm) {
    MainFlutterWindow.activePlayerItems.add(self)
    let target = MainFlutterWindow.shouldNormalizePitch ? AVAudioTimePitchAlgorithm.timeDomain : AVAudioTimePitchAlgorithm.varispeed
    self.merlin_setAudioTimePitchAlgorithm(target)
  }

  @objc func merlin_initWithAsset(_ asset: AVAsset) -> AVPlayerItem {
    let item = self.merlin_initWithAsset(asset)
    MainFlutterWindow.activePlayerItems.add(item)
    let target = MainFlutterWindow.shouldNormalizePitch ? AVAudioTimePitchAlgorithm.timeDomain : AVAudioTimePitchAlgorithm.varispeed
    item.merlin_setAudioTimePitchAlgorithm(target)
    return item
  }
}

class MainFlutterWindow: NSWindow {
  private let pathMonitor = NWPathMonitor()
  static var shouldNormalizePitch: Bool = true
  static let activePlayerItems = NSHashTable<AVPlayerItem>.weakObjects()

  private static let swizzleOnce: Void = {
    if let origSetter = class_getInstanceMethod(AVPlayerItem.self, #selector(setter: AVPlayerItem.audioTimePitchAlgorithm)),
       let swizSetter = class_getInstanceMethod(AVPlayerItem.self, #selector(AVPlayerItem.merlin_setAudioTimePitchAlgorithm(_:))) {
      method_exchangeImplementations(origSetter, swizSetter)
    }
    if let origInit = class_getInstanceMethod(AVPlayerItem.self, NSSelectorFromString("initWithAsset:")),
       let swizInit = class_getInstanceMethod(AVPlayerItem.self, #selector(AVPlayerItem.merlin_initWithAsset(_:))) {
      method_exchangeImplementations(origInit, swizInit)
    }
  }()

  static func setPitchNormalization(_ normalize: Bool) {
    shouldNormalizePitch = normalize
    let target: AVAudioTimePitchAlgorithm = normalize ? .timeDomain : .varispeed
    for item in activePlayerItems.allObjects {
      item.merlin_setAudioTimePitchAlgorithm(target)
    }
  }

  override func awakeFromNib() {
    _ = MainFlutterWindow.swizzleOnce

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    pathMonitor.start(queue: DispatchQueue.global(qos: .background))

    let networkChannel = FlutterMethodChannel(
      name: "com.podcastmerlin.app/network",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    networkChannel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "getNetworkInfo" {
        var ssid: String? = nil
        var isWifi = false
        if let interface = CWWiFiClient.shared().interface() {
          ssid = interface.ssid()
          isWifi = interface.powerOn()
        }
        let currentPath = self?.pathMonitor.currentPath
        let isEthernet = currentPath?.usesInterfaceType(.wiredEthernet) ?? false
        let isCellular = currentPath?.usesInterfaceType(.cellular) ?? false
        if let usesWifi = currentPath?.usesInterfaceType(.wifi), usesWifi {
          isWifi = true
        }

        let map: [String: Any?] = [
          "isConnected": currentPath?.status == .satisfied,
          "isWifi": isWifi || (ssid != nil && !ssid!.isEmpty),
          "isEthernet": isEthernet,
          "isCellular": isCellular,
          "ssid": ssid
        ]
        result(map)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let pitchChannel = FlutterMethodChannel(
      name: "com.podcastmerlin.app/audio_pitch",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    pitchChannel.setMethodCallHandler { (call, result) in
      if call.method == "setNormalizePitch" {
        if let args = call.arguments as? [String: Any],
           let normalize = args["normalize"] as? Bool {
          MainFlutterWindow.setPitchNormalization(normalize)
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected normalize boolean", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
