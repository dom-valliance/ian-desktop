import CoreMediaIO
import Foundation
import os

/// Reports whether a camera is running in any process. A protocol so tests inject a fake.
@MainActor
public protocol CameraMonitoring: AnyObject {
  var isLive: Bool { get }
  /// Starts observing. `onChange` runs on the main actor each time `isLive` may have changed.
  func start(onChange: @escaping @MainActor () -> Void)
  func stop()
}

/// Reads CoreMediaIO's "device is running somewhere" property across every video device, and
/// listens for changes to it and to the device list. Reading the property needs no camera
/// permission and does not open a device.
@MainActor
public final class CoreMediaCameraMonitor: CameraMonitoring {
  private static let log = Logger(subsystem: "ai.valliance.ian.desktop", category: "camera")

  public private(set) var isLive = false

  private var onChange: (@MainActor () -> Void)?
  private var watchedDevices: [CMIOObjectID] = []
  // The block is added to and removed from CoreMediaIO by identity, so the same instance is kept.
  private var listener: CMIOObjectPropertyListenerBlock?

  public init() {}

  public func start(onChange: @escaping @MainActor () -> Void) {
    guard listener == nil else { return }
    self.onChange = onChange
    // CoreMediaIO calls the block on the queue given below, the main queue.
    let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
      Task { @MainActor in self?.refresh() }
    }
    listener = block
    var devicesAddress = Self.address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    let status = CMIOObjectAddPropertyListenerBlock(
      CMIOObjectID(kCMIOObjectSystemObject), &devicesAddress, .main, block)
    if status != noErr {
      Self.log.error("camera device list listener failed: \(status, privacy: .public)")
    }
    refresh()
  }

  public func stop() {
    guard let block = listener else { return }
    var devicesAddress = Self.address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    CMIOObjectRemovePropertyListenerBlock(
      CMIOObjectID(kCMIOObjectSystemObject), &devicesAddress, .main, block)
    unwatchDevices()
    listener = nil
    onChange = nil
    isLive = false
  }

  /// Re-reads the device list and every device's running state, then reports the result.
  private func refresh() {
    guard let block = listener else { return }
    let devices = Self.videoDevices()
    if devices != watchedDevices {
      unwatchDevices()
      var runningAddress = Self.address(
        CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
      for device in devices {
        CMIOObjectAddPropertyListenerBlock(device, &runningAddress, .main, block)
      }
      watchedDevices = devices
    }
    let live = devices.contains(where: Self.isRunning)
    if live != isLive {
      isLive = live
      onChange?()
    }
  }

  private func unwatchDevices() {
    guard let block = listener else { return }
    var runningAddress = Self.address(
      CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
    for device in watchedDevices {
      CMIOObjectRemovePropertyListenerBlock(device, &runningAddress, .main, block)
    }
    watchedDevices = []
  }

  private static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(
      mSelector: selector,
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
  }

  private static func videoDevices() -> [CMIOObjectID] {
    var address = address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    var size: UInt32 = 0
    let system = CMIOObjectID(kCMIOObjectSystemObject)
    guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0
    else { return [] }
    var devices = [CMIOObjectID](
      repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr
    else { return [] }
    return Array(devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
  }

  private static func isRunning(_ device: CMIOObjectID) -> Bool {
    var address = address(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
    var running: UInt32 = 0
    var used: UInt32 = 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &running) == noErr
    else { return false }
    return running != 0
  }
}
