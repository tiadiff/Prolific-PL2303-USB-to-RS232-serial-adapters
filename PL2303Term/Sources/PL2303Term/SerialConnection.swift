import Foundation
import Darwin
import IOKit

enum BaudRate: Int, CaseIterable, Identifiable {
    case b9600 = 9600
    case b19200 = 19200
    case b38400 = 38400
    case b57600 = 57600
    case b115200 = 115200
    
    var id: Int { rawValue }
    
    var speed: speed_t {
        switch self {
        case .b9600: return speed_t(B9600)
        case .b19200: return speed_t(B19200)
        case .b38400: return speed_t(B38400)
        case .b57600: return speed_t(B57600)
        case .b115200: return speed_t(B115200)
        }
    }
}

enum ConnectionType {
    case posix(path: String)
    case driver(driver: PL2303Driver)
}

@MainActor
@Observable
class SerialConnection {
    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
    }

    var isConnected = false
    var logLines: [LogLine] = []
    var currentLine: String = ""
    var error: String?
    
    // POSIX State
    private var fileDescriptor: Int32 = -1
    private var readTask: Task<Void, Never>?
    
    // Driver State
    private var driver: PL2303Driver?
    
    func connect(device: SerialDevice, baudRate: BaudRate) {
        disconnect()
        
        if let path = device.path {
            // POSIX Connection
            connectPosix(path: path, baudRate: baudRate)
        } else {
            // User-Space Driver Connection
            connectDriver(device: device, baudRate: baudRate)
        }
    }
    
    private func connectDriver(device: SerialDevice, baudRate: BaudRate) {
        // We need to find the io_service_t for this device again.
        // device.id is "USB-VID-PID-Serial"
        
        guard let service = findService(for: device) else {
            self.error = "Could not find USB service for device"
            return
        }
        
        let newDriver = PL2303Driver(service: service, uniqueID: device.id)
        if newDriver.connect(baudRate: baudRate) {
            self.driver = newDriver
            self.isConnected = true
            self.error = nil
            
            startDriverReading(driver: newDriver)
            
        } else {
            self.error = newDriver.error
        }
    }
    
    private func startDriverReading(driver: PL2303Driver) {
        readTask = Task {
            for await text in driver.textStream {
               self.processIncoming(text)
            }
        }
    }
    
    private func findService(for device: SerialDevice) -> io_service_t? {
        let usbMatcher = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        var usbIter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, usbMatcher as CFDictionary, &usbIter) == KERN_SUCCESS {
            while case let service = IOIteratorNext(usbIter), service != 0 {
                defer { IOObjectRelease(service) }
                
                 let vendor = getRegistryInt(service, key: "idVendor") ?? 0
                 let pid = getRegistryInt(service, key: "idProduct") ?? 0
                 let serial = getRegistryString(service, key: "USB Serial Number") ?? "Unknown"
                 
                 let uniqueID = "USB-\(String(format: "%04X", pid))-\(serial)"
                 if uniqueID == device.id {
                     IOObjectRetain(service)
                     IOObjectRelease(usbIter)
                     return service
                 }
            }
            IOObjectRelease(usbIter)
        }
        return nil
    }
    
    private func connectPosix(path: String, baudRate: BaudRate) {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        
        guard fd != -1 else {
            self.error = "Failed to open port: \(String(cString: strerror(errno)))"
            return
        }
        
        var options = termios()
        if tcgetattr(fd, &options) == -1 {
            self.error = "Failed to get attributes"
            close(fd)
            return
        }
        
        cfsetispeed(&options, baudRate.speed)
        cfsetospeed(&options, baudRate.speed)
        cfmakeraw(&options)
        
        if tcsetattr(fd, TCSANOW, &options) == -1 {
            self.error = "Failed to set attributes"
            close(fd)
            return
        }
        
        tcflush(fd, TCIOFLUSH)
        
        var flags = fcntl(fd, F_GETFL)
        flags &= ~O_NONBLOCK
        fcntl(fd, F_SETFL, flags)
        
        self.fileDescriptor = fd
        self.isConnected = true
        self.error = nil
        
        startPosixReading(fd: fd)
    }
    
    private func startPosixReading(fd: Int32) {
        let stream = AsyncStream<String> { continuation in
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            
            let task = Task.detached {
                defer { buffer.deallocate() }
                while !Task.isCancelled {
                    let bytesRead = read(fd, buffer, bufferSize)
                    if bytesRead > 0 {
                        let data = Data(bytes: buffer, count: bytesRead)
                        // Use lossy conversion to ensure data is seen
                        let str = String(decoding: data, as: UTF8.self)
                        continuation.yield(str)
                    } else if bytesRead == -1 {
                        try? await Task.sleep(nanoseconds: 100_000_000) 
                    } else {
                        break 
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        
        readTask = Task {
            for await text in stream {
                self.processIncoming(text)
            }
        }
    }
    
    private func processIncoming(_ text: String) {
        // Append to current line buffer
        currentLine += text
        
        // Scan for newlines
        // If we find a newline, we take everything before it as a LogLine
        // and put it at the TOP of logLines.
        
        while let range = currentLine.range(of: "\n") {
            let lineContent = String(currentLine[..<range.lowerBound])
            
            // Should we trim control characters like \r? Probably yes for UI clarity.
            let trimmed = lineContent.trimmingCharacters(in: .controlCharacters)
            if !trimmed.isEmpty {
                 logLines.append(LogLine(text: trimmed))
            }
            
            // Remove the processed line AND the newline character from currentLine
            currentLine.removeSubrange(..<range.upperBound)
        }
    }
    
    func disconnect() {
        readTask?.cancel()
        
        if fileDescriptor != -1 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        
        if let driver = driver {
            driver.disconnect()
            self.driver = nil
        }
        
        isConnected = false
    }
    
    func clearLogs() {
        logLines.removeAll()
        currentLine = ""
    }
    
    func send(text: String) {
        if fileDescriptor != -1 {
            guard let data = text.data(using: .utf8) else { return }
            let fd = self.fileDescriptor
            data.withUnsafeBytes { ptr in
                guard let baseAddress = ptr.baseAddress else { return }
                _ = write(fd, baseAddress, ptr.count)
            }
        } else if let driver = driver {
            driver.send(text: text)
        }
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
