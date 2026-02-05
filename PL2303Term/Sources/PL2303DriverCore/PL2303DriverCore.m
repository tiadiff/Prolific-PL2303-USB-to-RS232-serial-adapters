#import "PL2303DriverCore.h"
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>

@implementation PL2303NativeDriver {
    io_service_t _service;
    IOUSBDeviceInterface300 **_deviceInterface;
    IOUSBInterfaceInterface300 **_interfaceInterface;
    
    UInt8 _bulkInPipe;
    UInt8 _bulkOutPipe;
    
    BOOL _forceStopReader;
}

- (instancetype)initWithService:(io_service_t)service {
    self = [super init];
    if (self) {
        _service = service;
        IOObjectRetain(_service);
    }
    return self;
}

- (void)dealloc {
    [self disconnect];
    if (_service) {
        IOObjectRelease(_service);
    }
}

- (BOOL)connectWithBaudRate:(int)baudRate error:(NSError **)error {
    SInt32 score;
    IOCFPlugInInterface **plugin = NULL;
    kern_return_t kr;
    
    // Create Plugin Interace
    kr = IOCreatePlugInInterfaceForService(_service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (kr != kIOReturnSuccess || !plugin) {
        if (error) *error = [NSError errorWithDomain:@"PL2303" code:kr userInfo:@{NSLocalizedDescriptionKey: @"Failed to create plugin interface"}];
        return NO;
    }
    
    // Get Device Interface
    HRESULT res = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID300), (LPVOID *)&_deviceInterface);
    (*plugin)->Release(plugin);
    
    if (res != 0 || !_deviceInterface) {
        if (error) *error = [NSError errorWithDomain:@"PL2303" code:res userInfo:@{NSLocalizedDescriptionKey: @"Failed to query device interface"}];
        return NO;
    }
    
    // Open Device
    kr = (*_deviceInterface)->USBDeviceOpen(_deviceInterface);
    if (kr != kIOReturnSuccess) {
        // Try opening seize?
        kr = (*_deviceInterface)->USBDeviceOpenSeize(_deviceInterface);
        if (kr != kIOReturnSuccess) {
            (*_deviceInterface)->Release(_deviceInterface);
            _deviceInterface = NULL;
            if (error) *error = [NSError errorWithDomain:@"PL2303" code:kr userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to open device: 0x%08x", kr]}];
            return NO;
        }
    }
    
    // Set Configuration
    (*_deviceInterface)->SetConfiguration(_deviceInterface, 1);
    
    // Find Interface
    IOUSBFindInterfaceRequest request;
    request.bInterfaceClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceSubClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
    request.bAlternateSetting = kIOUSBFindInterfaceDontCare;
    
    io_iterator_t iter = 0;
    kr = (*_deviceInterface)->CreateInterfaceIterator(_deviceInterface, &request, &iter);
    
    io_service_t interfaceService = IOIteratorNext(iter);
    if (iter) IOObjectRelease(iter);
    
    if (!interfaceService) {
        if (error) *error = [NSError errorWithDomain:@"PL2303" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"No interface found"}];
        [self disconnect];
        return NO;
    }
    
    // Create Interface Plugin
    kr = IOCreatePlugInInterfaceForService(interfaceService, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(interfaceService);
    
    if (kr != kIOReturnSuccess || !plugin) {
        if (error) *error = [NSError errorWithDomain:@"PL2303" code:kr userInfo:@{NSLocalizedDescriptionKey: @"Failed to create interface plugin"}];
        [self disconnect];
        return NO;
    }
    
    // Get Interface Interface
    res = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&_interfaceInterface);
    (*plugin)->Release(plugin);
    
    if (res != 0 || !_interfaceInterface) {
        if (error) *error = [NSError errorWithDomain:@"PL2303" code:res userInfo:@{NSLocalizedDescriptionKey: @"Failed to query interface interface"}];
        [self disconnect];
        return NO;
    }
    
    // Open Interface
    kr = (*_interfaceInterface)->USBInterfaceOpen(_interfaceInterface);
    if (kr != kIOReturnSuccess) {
        // Try Seize
        kr = (*_interfaceInterface)->USBInterfaceOpenSeize(_interfaceInterface);
        if (kr != kIOReturnSuccess) {
             if (error) *error = [NSError errorWithDomain:@"PL2303" code:kr userInfo:@{NSLocalizedDescriptionKey: @"Failed to open interface"}];
             [self disconnect];
             return NO;
        }
    }
    
    [self findPipes];
    
    if (![self initializePL2303WithBaudRate:baudRate]) {
        if (error) *error = [NSError errorWithDomain:@"PL2303" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Initialization failed"}];
        [self disconnect];
        return NO;
    }
    
    _isConnected = YES;
    return YES;
}

- (void)findPipes {
    UInt8 numEndpoints;
    (*_interfaceInterface)->GetNumEndpoints(_interfaceInterface, &numEndpoints);
    
    for (int i = 1; i <= numEndpoints; i++) {
        UInt8 direction;
        UInt8 number;
        UInt8 transferType;
        UInt16 maxPacketSize;
        UInt8 interval;
        
        (*_interfaceInterface)->GetPipeProperties(_interfaceInterface, i, &direction, &number, &transferType, &maxPacketSize, &interval);
        
        if (transferType == kUSBBulk) {
            if (direction == kUSBIn) {
                _bulkInPipe = i;
                printf("PL2303Driver: Found Bulk IN Pipe: %d\n", i);
            } else if (direction == kUSBOut) {
                _bulkOutPipe = i;
                printf("PL2303Driver: Found Bulk OUT Pipe: %d\n", i);
            }
        }
    }
}

- (BOOL)vendorWriteRequest:(UInt8)request value:(UInt16)value index:(UInt16)index {
    IOUSBDevRequest req;
    req.bmRequestType = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice);
    req.bRequest = request;
    req.wValue = value;
    req.wIndex = index;
    req.wLength = 0;
    req.pData = NULL;
    
    kern_return_t kr = (*_deviceInterface)->DeviceRequest(_deviceInterface, &req);
    return kr == kIOReturnSuccess;
}

- (BOOL)initializePL2303WithBaudRate:(int)baudRate {
    [self vendorWriteRequest:1 value:0x0404 index:0];
    [self vendorWriteRequest:1 value:0x0404 index:1];
    
    // Line Coding
    struct {
        UInt32 dwDTERate;
        UInt8 bCharFormat;
        UInt8 bParityType;
        UInt8 bDataBits;
    } __attribute__((packed)) lineCoding;
    
    lineCoding.dwDTERate = CFSwapInt32HostToLittle(baudRate);
    lineCoding.bCharFormat = 0;
    lineCoding.bParityType = 0;
    lineCoding.bDataBits = 8;
    
    IOUSBDevRequest req;
    req.bmRequestType = USBmakebmRequestType(kUSBOut, kUSBClass, kUSBInterface);
    req.bRequest = 0x20; // SET_LINE_CODING
    req.wValue = 0;
    req.wIndex = 0; // Interface 0
    req.wLength = 7;
    req.pData = &lineCoding;
    
    kern_return_t kr = (*_deviceInterface)->DeviceRequest(_deviceInterface, &req);
    if (kr != kIOReturnSuccess) printf("SetLineCoding failed: 0x%x\n", kr);
    
    return YES; // Proceed even if fails
}

- (void)disconnect {
    _forceStopReader = YES;
    if (_interfaceInterface) {
        (*_interfaceInterface)->USBInterfaceClose(_interfaceInterface);
        (*_interfaceInterface)->Release(_interfaceInterface);
        _interfaceInterface = NULL;
    }
    if (_deviceInterface) {
        (*_deviceInterface)->USBDeviceClose(_deviceInterface);
        (*_deviceInterface)->Release(_deviceInterface);
        _deviceInterface = NULL;
    }
    _isConnected = NO;
}

- (void)writeData:(NSData *)data {
    if (!_interfaceInterface || !_bulkOutPipe) return;
    (*_interfaceInterface)->WritePipe(_interfaceInterface, _bulkOutPipe, (void *)[data bytes], (UInt32)[data length]);
}

- (void)startReadingWithBlock:(void (^)(NSData *data))block {
    _forceStopReader = NO;
    printf("PL2303Driver: Starting read loop on pipe %d\n", _bulkInPipe);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UInt32 bufferSize = 64;
        char buffer[64];
        
        while (!self->_forceStopReader && self->_interfaceInterface) {
            UInt32 actualLen = bufferSize;
            kern_return_t kr = (*self->_interfaceInterface)->ReadPipe(self->_interfaceInterface, self->_bulkInPipe, buffer, &actualLen);
            
            if (kr == kIOReturnSuccess) {
                if (actualLen > 0) {
                    printf("PL2303Driver: Read %d bytes\n", actualLen);
                    NSData *data = [NSData dataWithBytes:buffer length:actualLen];
                    if (block) block(data);
                }
            } else if (kr == kIOReturnNotResponding) {
                 printf("PL2303Driver: Device not responding (0x%x)\n", kr);
                self->_forceStopReader = YES;
            } else if (kr != kIOReturnSuccess) {
                 if (kr != 0xe00002ed) { // timeout
                     printf("PL2303Driver: Read Error: 0x%x\n", kr);
                 }
                [NSThread sleepForTimeInterval:0.1];
            }
        }
        printf("PL2303Driver: Read loop stopped\n");
    });
}

@end
