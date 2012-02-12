//
//  GCDTcpConnection.h
//  GCDNetworking
//
//  Created by Lorenzo Masini on 06/02/12.
//  Copyright (c) 2012 Develer srl. All rights reserved.
//

@class NSHost, NSData, NSString;

@protocol GCDTcpConnectionDelegate;

@interface GCDTcpConnection : NSObject

@property (readonly, nonatomic, retain) NSHost *peerHost;
@property (readonly, nonatomic, assign) uint16_t peerPort;

@property (weak) id<GCDTcpConnectionDelegate> delegate;
@property (assign) dispatch_queue_t delegateQueue;


+ (void) connectToHost:(NSHost *)host
                  port:(uint16_t)port
          withDelegate:(id<GCDTcpConnectionDelegate>) delegate
         delegateQueue:(dispatch_queue_t)queue;

- (id)initWithFileDescriptor:(int)fileDescriptor;

- (void)disconnect;

- (NSUInteger)bytesAvaiable;

- (NSData *)readDataToLength:(NSUInteger)length;
- (void)writeData:(NSData *)data;

@end

@interface GCDTcpConnection (LineIO)

- (BOOL)canReadLineWithSeparator:(NSString *)separator
                   usingEncoding:(NSStringEncoding)encoding;

- (NSString *)readLineWithSeparator:(NSString *)separator
                      usingEncoding:(NSStringEncoding)encoding;

- (void)writeLine:(NSString *)line
    withSeparator:(NSString *)separator
    usingEncoding:(NSStringEncoding)encoding;

@end

@protocol GCDTcpConnectionDelegate <NSObject>

- (void)didConnectWithConnection:(GCDTcpConnection *)connection;
- (void)didReceiveDataOnConnection:(GCDTcpConnection *)connection;
- (void)didFinishWriteOnConnection:(GCDTcpConnection *)connection;

@end