//
//  GCDTcpSocket.h
//  GCDNetworking
//
//  Created by Lorenzo Masini on 31/07/12.
//  Copyright (c) 2012 Develer srl. All rights reserved.
//

@protocol GCDTcpSocketDelegate;

@interface GCDTcpSocket : NSObject

@property (readonly) NSHost *host;
@property (readonly) uint16_t port;

@property (weak) id<GCDTcpSocketDelegate> delegate;
@property (assign) dispatch_queue_t delegateQueue;

- (id)initWithHost:(NSHost *)host port:(uint16_t)port;

- (void)connect;
- (void)disconnect;

- (NSUInteger)bytesAvaiable;

- (NSData *)readDataToLength:(NSUInteger)length;
- (void)writeData:(NSData *)data;

@end

@interface GCDTcpSocket (Blocking)

- (BOOL)waitForConnectionNotifyWithTimeout:(NSTimeInterval)timeout;
- (BOOL)waitForDisconnecionNotifyWithTimeout:(NSTimeInterval)timeout;

- (BOOL)waitForReadNotifyWithTimeout:(NSTimeInterval)timeout;
- (BOOL)waitForWriteNotifyWithTimeout:(NSTimeInterval)timeout;

@end

@interface GCDTcpSocket (LineIO)

- (BOOL)canReadLineWithSeparator:(NSString *)separator
                   usingEncoding:(NSStringEncoding)encoding;

- (NSString *)readLineWithSeparator:(NSString *)separator
                      usingEncoding:(NSStringEncoding)encoding;

- (void)writeLine:(NSString *)line
    withSeparator:(NSString *)separator
    usingEncoding:(NSStringEncoding)encoding;

@end

@protocol GCDTcpSocketDelegate <NSObject>

@optional
- (void)socket:(GCDTcpSocket *)socket didConnectToHost:(NSHost *)host port:(uint16_t)port;
- (void)socket:(GCDTcpSocket *)socket didDisconnectFromHost:(NSHost *)host port:(uint16_t)port;

- (void)socket:(GCDTcpSocket *)socket didReceive:(NSUInteger)bytes;
- (void)socket:(GCDTcpSocket *)socket didWrite:(NSUInteger)bytes;

- (void)socket:(GCDTcpSocket *)socket didHaveError:(NSError *)error;

@end
