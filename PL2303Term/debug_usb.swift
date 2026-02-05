import Foundation
import IOKit
import IOKit.usb

func probe(className: String) {
    print("Probing class: \(className)")
    let matchingDict = IOServiceMatching(className) as NSMutableDictionary
    // matchingDict["idVendor"] = NSNumber(value: 0x067B) 
    
    var iter: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict as CFDictionary, &iter)
    
    if kr == KERN_SUCCESS {
        var count = 0
        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }
            count += 1
            
            let name = getRegistryString(service, key: "USB Product Name") ?? "Unknown"
            let vendor = getRegistryInt(service, key: "idVendor") ?? 0
            let product = getRegistryInt(service, key: "idProduct") ?? 0
            
            print("Found: \(name) (VID: 0x\(String(format: "%04X", vendor)), PID: 0x\(String(format: "%04X", product)))")
        }
        IOObjectRelease(iter)
        print("Total found for \(className): \(count)")
    } else {
        print("Failed to get matching services: \(kr)")
    }
}

func getRegistryString(_ service: io_object_t, key: String) -> String? {
    if let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) {
        let nsProp = prop.takeRetainedValue()
        if let str = nsProp as? String { return str }
    }
    return nil
}

func getRegistryInt(_ service: io_object_t, key: String) -> Int? {
    if let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) {
        let nsProp = prop.takeRetainedValue()
        if let val = nsProp as? Int { return val }
    }
    return nil
}

print("Starting Probe...")
probe(className: "IOUSBHostDevice")
probe(className: "IOUSBDevice")
