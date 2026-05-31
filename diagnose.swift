import Foundation
import IOKit
import IOKit.hid

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let match: [String: Any] = [:]
IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

let allDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
print("Found \(allDevices.count) HID devices:\n")

var devices: [(name: String, vendor: Int, product: Int, transport: String)] = []
for device in allDevices {
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
    let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
    let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
    devices.append((name, vendor, product, transport))
}

devices.sort { $0.name < $1.name }

for d in devices {
    let v = String(format: "%04X", d.vendor)
    let p = String(format: "%04X", d.product)
    print("Name:      \(d.name)")
    print("VendorID:  0x\(v) (\(d.vendor))")
    print("ProductID: 0x\(p) (\(d.product))")
    print("Transport: \(d.transport)")
    print("---")
}
