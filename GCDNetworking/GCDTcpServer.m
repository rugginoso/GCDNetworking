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
#import <netdb.h>

@interface GCDTcpServer ()

@property BOOL listening;

@end

@implementation GCDTcpServer
{
    dispatch_queue_t _socketQueue;

    dispatch_source_t _source;

    NSMutableArray * _incomingConnections;
}

- (id)initWithListenAddress:(NSString *)host port:(uint16_t)port
{
    if (self = [super init]) {
        _host = host;
        _port = port;

        _socketQueue = dispatch_queue_create("GCDNetworking.AcceptQueue", DISPATCH_QUEUE_SERIAL);
        _delegateQueue = dispatch_get_main_queue();

        _incomingConnections = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void)startListen
{
    __unsafe_unretained GCDTcpServer *wself = self;

    dispatch_async(wself->_socketQueue, ^(void) {
        int fd = -1;

        struct addrinfo *info;
        struct addrinfo hints = {AI_ADDRCONFIG|AI_PASSIVE, PF_UNSPEC, SOCK_STREAM, IPPROTO_TCP};
        int ret;
        if ((ret = getaddrinfo([wself->_host cStringUsingEncoding:NSUTF8StringEncoding],
                               [[NSString stringWithFormat:@"%u", wself->_port] cStringUsingEncoding:NSUTF8StringEncoding],
                               &hints,
                               &info)) != 0) {
            NSLog(@"Error resolving name: %s", gai_strerror(ret));
            return;
        }

        if ((fd = socket(info->ai_family, info->ai_socktype, 0)) < 0)
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

        if (bind(fd, info->ai_addr, info->ai_addrlen) < 0) {
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

        if (listen(fd, 5) < 0) {
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
        freeaddrinfo(info);

        // Create dispatch sources
        wself->_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                                fd,
                                                0,
                                                wself->_socketQueue);

        // Accept handler
        dispatch_source_set_event_handler(wself->_source, ^(void) {
            NSUInteger estimated = dispatch_source_get_data(wself->_source);
            NSUInteger accepted = 0;

            while (estimated > 0) {
                int client_fd = -1;

                if ((client_fd = accept(fd, NULL, NULL)) < 0) {
                    if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(server:didHaveError:)]) {
                        NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                             code:errno
                                                         userInfo:nil];

                        dispatch_async(wself->_delegateQueue, ^(void) {
                            [wself->_delegate server:wself didHaveError:error];
                        });
                    }
                    continue;
                }

                GCDTcpSocket *client = [[GCDTcpSocket alloc] initWithFileDescriptior:client_fd];
                [wself->_incomingConnections addObject:client];

                estimated--;
                accepted++;
            }

            if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(server:didAcceptNewConnections:)]) {
                dispatch_async(wself->_delegateQueue, ^(void) {
                    [wself->_delegate server:wself didAcceptNewConnections:accepted];
                });
            }
        });

        dispatch_source_set_cancel_handler(wself->_source, ^(void) {
            close(fd);
        });

        dispatch_resume(wself->_source);

        wself.listening = YES;

        if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(server:didStartListeningOnHost:port:)]) {
            dispatch_async(wself->_delegateQueue, ^(void) {
                [wself->_delegate server:wself didStartListeningOnHost:wself->_host port:wself->_port];
            });
        }
    });
}

- (void)stopListen
{
    dispatch_source_cancel(_source);
    _source = nil;

    self.listening = NO;

    __unsafe_unretained GCDTcpServer *wself = self;

    if (self.delegate && [self.delegate respondsToSelector:@selector(server:didStopListeningOnHost:port:)]) {
        dispatch_async(self->_delegateQueue, ^(void) {
            [wself->_delegate server:wself didStopListeningOnHost:wself->_host port:wself->_port];
        });
    }

    // FIXME: Maybe explicitly disconnect all the clients?
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
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + timeout;

    do {
        if (self.isListening)
            return YES;
    } while (CFAbsoluteTimeGetCurrent() <= end);

    return NO;
}

- (BOOL)waitForStopListeningNotifyWithTimeout:(NSTimeInterval)timeout
{
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + timeout;

    do {
        if (!self.isListening)
            return YES;
    } while (CFAbsoluteTimeGetCurrent() <= end);

    return NO;
}

- (BOOL)waitForNewConnectionNotifyWithTimeout:(NSTimeInterval)timeout
{
    __unsafe_unretained GCDTcpServer *wself = self;
    __block BOOL result = NO;

    dispatch_block_t block = ^(void) {
        result = wself->_incomingConnections.count > 0;
    };

    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + timeout;

    do {
        if (dispatch_get_current_queue() == _socketQueue)
            block();
        else
            dispatch_sync(_socketQueue, block);

        if (result)
            return YES;

    } while (CFAbsoluteTimeGetCurrent() <= end);
    
    return NO;
}

@end

