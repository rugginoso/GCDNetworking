//
//  GCDTcpServer.m
//  GCDNetworking
//
//  Created by Lorenzo Masini on 03/08/12.
//  Copyright (c) 2012 Develer srl. All rights reserved.
//

#import "GCDTcpServer.h"

#import <Foundation/Foundation.h>
#import <GCDNetworking/GCDTcpSocket.h>

#import <sys/types.h>
#import <sys/socket.h>
#import <arpa/inet.h>

@interface GCDTcpServer ()

@property BOOL hasIncomingConnections;
@property BOOL isListening;

@end

@implementation GCDTcpServer
{
    int _fd;

    dispatch_queue_t _socketQueue;

    dispatch_source_t _source;

    NSMutableArray * _incomingConnections;
}

- (id)initWithListenAddress:(NSHost *)host port:(uint16_t)port
{
    if (self = [super init]) {
        _host = host;
        _port = port;

        _socketQueue = dispatch_queue_create("GCDTcpServer", DISPATCH_QUEUE_SERIAL);
        _delegateQueue = dispatch_get_main_queue();

        _fd = -1;

        _incomingConnections = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void)startListen
{
    __unsafe_unretained GCDTcpServer *wself = self;

    dispatch_async(wself->_socketQueue, ^(void) {
        // Connect to host
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(struct sockaddr_in));

        const char *hostname = [[wself->_host address] cStringUsingEncoding:NSASCIIStringEncoding];

        inet_aton(hostname, &addr.sin_addr);
        addr.sin_port = htons(wself->_port);

        if ((wself->_fd = socket(PF_INET, SOCK_STREAM, 0)) < 0)
        {
            if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(server:didHaveError:)]) {
                NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                     code:errno
                                                 userInfo:nil];

                dispatch_async(wself->_delegateQueue, ^(void) {
                    [wself->_delegate server:wself didHaveError:error];
                });
            }
            
            return;
        }

        if (bind(wself->_fd, (struct sockaddr *) &addr, sizeof(struct sockaddr_in)) < 0) {
            if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(server:didHaveError:)]) {
                NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                     code:errno
                                                 userInfo:nil];

                dispatch_async(wself->_delegateQueue, ^(void) {
                    [wself->_delegate server:wself didHaveError:error];
                });
            }

            return;
        }

        if (listen(wself->_fd, 5) < 0) {
            if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(server:didHaveError:)]) {
                NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                     code:errno
                                                 userInfo:nil];

                dispatch_async(wself->_delegateQueue, ^(void) {
                    [wself->_delegate server:wself didHaveError:error];
                });
            }

            return;
        }


        // Create dispatch sources
        wself->_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                                wself->_fd,
                                                0,
                                                wself->_socketQueue);

        // Accept handler
        dispatch_source_set_event_handler(wself->_source, ^(void) {
            NSUInteger estimated = dispatch_source_get_data(wself->_source);
            NSLog(@"Estimated connections: %lu", estimated);

            int client_fd = -1;

            if ((client_fd = accept(wself->_fd, NULL, NULL)) < 0) {
                if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(server:didHaveError:)]) {
                    NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                         code:errno
                                                     userInfo:nil];

                    dispatch_async(wself->_delegateQueue, ^(void) {
                        [wself->_delegate server:wself didHaveError:error];
                    });
                }
            }

            GCDTcpSocket *client = [[GCDTcpSocket alloc] initWithFileDescriptior:client_fd];
            [wself->_incomingConnections addObject:client];

            wself.hasIncomingConnections = YES;

            if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(server:didAcceptNewConnections:)]) {
                dispatch_async(wself->_delegateQueue, ^(void) {
                    [wself->_delegate server:wself didAcceptNewConnections:wself->_incomingConnections.count];
                });
            }
        });

        dispatch_source_set_cancel_handler(wself->_source, ^(void) {
            close(wself->_fd);
        });

        dispatch_resume(wself->_source);

        wself.isListening = YES;

        if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(server:didStartListeningOnHost:port:)]) {
            dispatch_async(wself->_delegateQueue, ^(void) {
                [wself->_delegate server:wself didStopListeningOnHost:wself->_host port:wself->_port];
            });
        }
    });
}

- (void)stopListen
{
    dispatch_source_cancel(_source);
    _source = nil;

    self.isListening = NO;

    __unsafe_unretained GCDTcpServer *wself = self;

    if (self.delegate && [self.delegate respondsToSelector:@selector(server:didStopListeningOnHost:port:)]) {
        dispatch_async(self->_delegateQueue, ^(void) {
            [wself->_delegate server:wself didStopListeningOnHost:wself->_host port:wself->_port];
        });
    }

    // FIXME: Maybe explicitly disconnect al the clients?
}

- (GCDTcpSocket *)nextPendingConnection
{
    __unsafe_unretained GCDTcpServer *wself = self;
    __block GCDTcpSocket *result = nil;

    dispatch_block_t block = ^(void) {
        if (wself->_incomingConnections.count > 0) {
            result = [wself->_incomingConnections objectAtIndex:0];
            [wself->_incomingConnections removeObjectAtIndex:0];
        }
    };

    if (dispatch_get_current_queue() == _socketQueue)
        block();
    else
        dispatch_sync(_socketQueue, block);
    
    return result;
}

@end

@implementation GCDTcpServer (Blocking)

- (BOOL)waitForStartListeningNotifyWithTimeout:(NSTimeInterval)timeout
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:timeout];

    do {
        if (self.isListening)
            return YES;
    } while ([[NSDate date] isLessThanOrEqualTo:end]);

    return NO;
}

- (BOOL)waitForStopListeningNotifyWithTimeout:(NSTimeInterval)timeout
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:timeout];

    do {
        if (!self.isListening)
            return YES;
    } while ([[NSDate date] isLessThanOrEqualTo:end]);

    return NO;
}

- (BOOL)waitForNewConnectionNotifyWithTimeout:(NSTimeInterval)timeout
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:timeout];

    do {
        if (self.hasIncomingConnections)
            return YES;
    } while ([[NSDate date] isLessThanOrEqualTo:end]);

    self.hasIncomingConnections = NO;

    return NO;
}

@end
