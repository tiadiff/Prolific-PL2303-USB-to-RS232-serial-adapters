#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

NS_ASSUME_NONNULL_BEGIN

@interface PL2303NativeDriver : NSObject

@property (nonatomic, readonly) BOOL isConnected;

- (instancetype)initWithService:(io_service_t)service;

- (BOOL)connectWithBaudRate:(int)baudRate error:(NSError **)error;
- (void)disconnect;

- (void)writeData:(NSData *)data;
- (void)startReadingWithBlock:(void (^)(NSData *data))block;

@end

NS_ASSUME_NONNULL_END
