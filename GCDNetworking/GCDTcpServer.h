//
//  GCDTcpServer.h
//  GCDNetworking
//
//  Created by Lorenzo Masini on 03/08/12.
//  Copyright (c) 2012 Develer srl. All rights reserved.
//

@protocol GCDTcpServerDelegate;

@interface GCDTcpServer : NSObject

@property (readonly, strong) NSString *host;
@property (readonly) uint16_t port;

@property (weak) id<GCDTcpServerDelegate> delegate;
@property (assign) dispatch_queue_t delegateQueue;

@property (readonly, getter=isListening) BOOL listening;

- (id)initWithListenAddress:(NSString *)host port:(uint16_t)port;

- (void)startListen;
- (void)stopListen;

- (GCDTcpSocket *)nextPendingConnection;

@end

@interface GCDTcpServer (Blocking)

- (BOOL)waitForStartListeningNotifyWithTimeout:(NSTimeInterval)timeout;
- (BOOL)waitForStopListeningNotifyWithTimeout:(NSTimeInterval)timeout;

- (BOOL)waitForNewConnectionNotifyWithTimeout:(NSTimeInterval)timeout;

@end

@protocol GCDTcpServerDelegate <NSObject>
@optional

- (void)server:(GCDTcpServer *)server didStartListeningOnHost:(NSString *)host port:(uint16_t)port;
- (void)server:(GCDTcpServer *)server didStopListeningOnHost:(NSString *)host port:(uint16_t)port;

- (void)server:(GCDTcpServer *)server didAcceptNewConnections:(NSUInteger)connections;

- (void)server:(GCDTcpServer *)server didHaveError:(NSError *)error;

@end
