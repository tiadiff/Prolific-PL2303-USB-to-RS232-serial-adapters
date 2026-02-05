import Foundation
import IOKit
import IOKit.serial

struct SerialDevice: Identifiable, Hashable {
    let id: String 
    let name: String
    let isProlific: Bool
    let path: String? // Nil if raw USB without driver
}

@Observable
class SerialPortManager {
    var availableDevices: [SerialDevice] = []
    
    init() {
        refreshDevices()
    }
    
    func refreshDevices() {
        var devices: [SerialDevice] = []
        
        // 1. Find Serial Ports (Drivers loaded)
        let serialMatcher = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        serialMatcher[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        
        var serialIter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, serialMatcher as CFDictionary, &serialIter) == KERN_SUCCESS {
            while case let service = IOIteratorNext(serialIter), service != 0 {
                defer { IOObjectRelease(service) }
                if let path = getRegistryString(service, key: kIOCalloutDeviceKey) {
                    let name = getRegistryString(service, key: kIOTTYDeviceKey) ?? path
                    let isProlific = name.contains("usbserial") || name.contains("PL2303")
                    devices.append(SerialDevice(id: path, name: name, isProlific: isProlific, path: path))
                }
            }
            IOObjectRelease(serialIter)
        }
        
        // 2. Find Raw USB Devices (Prolific VID 0x067B)
        // Note: This matches raw USB devices. If a driver is loaded, we might see both.
        // We'll simplisticly add them if they don't look like they are already covered.
        
        // "IOUSBHostDevice" is the modern class, "IOUSBDevice" is legacy but often still works or bridges.
        // Let's try "IOUSBHostDevice" first, if empty try "IOUSBDevice".
        // Actually, let's stick to "IOUSBHostDevice" for macOS 15.
        
        let usbMatcher = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        // usbMatcher["idVendor"] = 0x067B // Dictionary matching unreliable
        
        var usbIter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, usbMatcher as CFDictionary, &usbIter) == KERN_SUCCESS {
            while case let service = IOIteratorNext(usbIter), service != 0 {
                defer { IOObjectRelease(service) }
                
                let vendor = getRegistryInt(service, key: "idVendor") ?? 0
                if vendor == 0x067B {
                    let pid = getRegistryInt(service, key: "idProduct") ?? 0
                    let name = getRegistryString(service, key: "USB Product Name") ?? "Prolific USB Device"
                    let serial = getRegistryString(service, key: "USB Serial Number") ?? "Unknown"
                    
                    // Unique ID
                    let uniqueID = "USB-\(String(format: "%04X", pid))-\(serial)"
                    
                    devices.append(SerialDevice(id: uniqueID, name: "USB: \(name) (PID: \(String(format: "%X", pid)))", isProlific: true, path: nil))
                }
            }
            IOObjectRelease(usbIter)
        }
        
        self.availableDevices = devices
    }
    
    private func getRegistryString(_ service: io_object_t, key: String) -> String? {
        if let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) {
            let nsProp = prop.takeRetainedValue()
            if let str = nsProp as? String {
                return str
            }
        }
        return nil
    }
    
    private func getRegistryInt(_ service: io_object_t, key: String) -> Int? {
        if let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) {
            let nsProp = prop.takeRetainedValue()
            if let val = nsProp as? Int {
                return val
            }
        }
        return nil
    }
}
