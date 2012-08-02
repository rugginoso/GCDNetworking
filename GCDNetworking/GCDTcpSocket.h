//
//  GCDTcpSocket.h
//  GCDNetworking
//
//  Created by Lorenzo Masini on 31/07/12.
//  Copyright (c) 2012 Develer srl. All rights reserved.
//

@interface GCDTcpSocket : NSObject
{
    int _fd;

    NSMutableData *_rbuffer;
    NSMutableData *_wbuffer;

    dispatch_queue_t _socketQueue;

    dispatch_source_t _rsource;
    dispatch_source_t _wsource;
}

@property (readonly) NSHost *host;
@property (readonly) uint16_t port;

@property (weak) id delegate;
@property (assign) dispatch_queue_t delegateQueue;


- (id)initWithHost:(NSHost *)host port:(uint16_t)port;

- (void)connect;
- (void)disconnect;

- (NSUInteger)bytesAvaiable;

- (NSData *)readDataToLength:(NSUInteger)length;
- (void)writeData:(NSData *)data;

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

@protocol GCDTcpSocketDelegate

@optional
- (void)socket:(GCDTcpSocket *)socket didConnectToHost:(NSHost *)host port:(uint16_t)port;
- (void)socket:(GCDTcpSocket *)socket didDisconnectFromHost:(NSHost *)host port:(uint16_t)port;

- (void)socket:(GCDTcpSocket *)socket didReceive:(NSUInteger)bytes;
- (void)socket:(GCDTcpSocket *)socket didWrite:(NSUInteger)bytes;

- (void)socket:(GCDTcpSocket *)socket didHaveError:(NSError *)error;

@end
