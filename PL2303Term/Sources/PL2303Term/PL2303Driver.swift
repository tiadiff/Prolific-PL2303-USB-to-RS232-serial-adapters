import Foundation
import IOKit
import PL2303DriverCore

@Observable
class PL2303Driver {
    var isConnected = false
    var error: String?
    
    // Stream for incoming data
    private let (stream, continuation) = AsyncStream<String>.makeStream()
    var textStream: AsyncStream<String> { stream }
    
    // private var streamContinuation: AsyncStream<String>.Continuation? // Removed
    
    private var nativeDriver: PL2303NativeDriver?
    private var service: io_service_t
    private var uniqueID: String
    
    init(service: io_service_t, uniqueID: String) {
        self.service = service
        IOObjectRetain(service)
        self.uniqueID = uniqueID
    }
    
    deinit {
        disconnect()
        IOObjectRelease(service)
    }
    
    func connect(baudRate: BaudRate) -> Bool {
        let driver = PL2303NativeDriver(service: service)
        
        do {
            try driver.connect(withBaudRate: Int32(baudRate.rawValue))
        } catch {
            self.error = error.localizedDescription
            return false
        }
        
        self.nativeDriver = driver
        self.isConnected = true
        
        // Start Reading
        // Use self.continuation directly
        let yieldTo = self.continuation
        driver.startReading { data in
            print("Swift Wrapper: Received \(data.count) bytes")
            // Use lossy conversion
            let str = String(decoding: data, as: UTF8.self)
            print("Swift Wrapper: Yielding: '\(str)'")
            yieldTo.yield(str)
        }
        
        return true
    }
    
    func disconnect() {
        nativeDriver?.disconnect()
        nativeDriver = nil
        isConnected = false
        // Don't finish stream here if we want to reuse? 
        // Actually usually we should finish it.
        // But we initialized it once. If we finish, we can't reuse this instance easily without re-init.
        // But disconnect implies done.
        // Ideally we shouldn't finish if we just disconnected?
        // Let's NOT finish it, or finish it only if deinit.
        // Or if we finish, we can't reconnect using same PL2303Driver instance.
        // Since SerialConnection creates NEW driver instance on connect, finishing is fine.
        continuation.finish()
    }
    
    func send(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        nativeDriver?.write(data)
    }
}
