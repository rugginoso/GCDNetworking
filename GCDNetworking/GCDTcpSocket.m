//
//  GCDTcpSocket.m
//  GCDNetworking
//
//  Created by Lorenzo Masini on 31/07/12.
//  Copyright (c) 2012 Develer srl. All rights reserved.
//

#import "GCDTcpSocket.h"

#import <Foundation/Foundation.h>

#import <sys/types.h>
#import <sys/socket.h>
#import <arpa/inet.h>


@implementation GCDTcpSocket

- (id)initWithHost:(NSHost *)host port:(uint16_t)port
{
    if (self = [super init]) {
        _host = host;
        _port = port;

        _wbuffer = [[NSMutableData alloc] init];
        _rbuffer = [[NSMutableData alloc] init];

        _socketQueue = dispatch_queue_create("GCDTcpSocket", DISPATCH_QUEUE_SERIAL);
        _delegateQueue = dispatch_get_main_queue();

        _fd = -1;
    }

    return self;
}

- (void)dealloc
{
    _socketQueue = nil;
    _host = nil;
    _wbuffer = nil;
    _rbuffer = nil;
}

- (void)connect
{
    __unsafe_unretained GCDTcpSocket *wself = self;

    dispatch_async(wself->_socketQueue, ^(void) {
        // Connect to host
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(struct sockaddr_in));

        const char *hostname = [[wself->_host address] cStringUsingEncoding:NSASCIIStringEncoding];

        inet_aton(hostname, &addr.sin_addr);
        addr.sin_port = htons(wself->_port);

        if ((wself->_fd = socket(PF_INET, SOCK_STREAM, 0)) < 0)
        {
            if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didHaveError:)]) {
                NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                     code:errno
                                                 userInfo:nil];

                dispatch_async(wself->_delegateQueue, ^(void) {
                    [wself->_delegate socket:wself didHaveError:error];
                });
            }

            return;
        }

        if (connect(wself->_fd, (struct sockaddr *) &addr, sizeof(struct sockaddr_in)) < 0) {
            if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didHaveError:)]) {
                NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                     code:errno
                                                 userInfo:nil];

                dispatch_async(wself->_delegateQueue, ^(void) {
                    [wself->_delegate socket:wself didHaveError:error];
                });
            }

            return;
        }

        // Create dispatch sources
        wself->_rsource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                            wself->_fd,
                                            0,
                                            wself->_socketQueue);

        wself->_wsource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE,
                                             wself->_fd,
                                             0,
                                             wself->_socketQueue);


        // Read handler
        dispatch_source_set_event_handler(wself->_rsource, ^(void) {
            NSUInteger estimated = dispatch_source_get_data(wself->_rsource);
            void *buf = malloc(estimated);

            ssize_t got = read(wself->_fd, buf, estimated);
            if (got < 0) {

                if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didHaveError:)]) {
                    NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                         code:errno
                                                     userInfo:nil];

                    dispatch_async(wself->_delegateQueue, ^(void) {
                        [wself->_delegate socket:wself didHaveError:error];
                    });
                }

                free(buf);

                [wself disconnect];

                return;
            }

            [wself->_rbuffer appendBytes:buf length:got];

            if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didReceive:)]) {
                dispatch_async(wself->_delegateQueue, ^(void) {
                    [wself->_delegate socket:wself didReceive:got];
                });
            }

            free(buf);
        });

        // Write handler
        dispatch_source_set_event_handler(wself->_wsource, ^(void) {
            ssize_t wrote = write(wself->_fd,
                                  wself->_wbuffer.bytes,
                                  wself->_wbuffer.length);

            if (wrote < 0) {
                if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didHaveError:)]) {
                    NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                         code:errno
                                                     userInfo:nil];

                    dispatch_async(wself->_delegateQueue, ^(void) {
                        [wself->_delegate socket:wself didHaveError:error];
                    });
                }

                [wself disconnect];

                return;
            }


            [wself->_wbuffer replaceBytesInRange:NSMakeRange(0, wrote)
                                        withBytes:NULL
                                           length:0];

            if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didWrite:)]) {
                dispatch_async(wself->_delegateQueue, ^(void) {
                    [wself->_delegate socket:wself didWrite:wrote];
                });
            }

            if (wself->_wbuffer.length == 0)
                dispatch_suspend(wself->_wsource);

        });

        // Cancel handler
        dispatch_block_t cancelHandler = ^(void) {
            close(wself->_fd);
        };
        
        dispatch_source_set_cancel_handler(wself->_rsource, cancelHandler);
        dispatch_source_set_cancel_handler(wself->_wsource, cancelHandler);
        
        dispatch_resume(wself->_rsource);

        if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didConnectToHost:port:)]) {
            dispatch_async(wself->_delegateQueue, ^(void) {
                [wself->_delegate socket:wself didConnectToHost:wself->_host port:wself->_port];
            });
        }
    });
}

- (void)disconnect
{
    dispatch_source_cancel(_rsource);

    // Resume writeSource to correctly call the cancel handler
    dispatch_resume(_wsource);
    dispatch_source_cancel(_wsource);

    _rsource = nil;
    _wsource = nil;

    __unsafe_unretained GCDTcpSocket *wself = self;

    if (self.delegate && [self.delegate respondsToSelector:@selector(socket:didDisconnectFromHost:port:)]) {
        dispatch_async(self->_delegateQueue, ^(void) {
            [wself->_delegate socket:wself didDisconnectFromHost:wself->_host port:wself->_port];
        });
    }
}

- (NSUInteger)bytesAvaiable
{
    __unsafe_unretained GCDTcpSocket *wself = self;
    __block NSUInteger result;

    dispatch_block_t block = ^(void) {
        result = wself->_rbuffer.length;
    };

    if (dispatch_get_current_queue() == _socketQueue)
        block();
    else
        dispatch_sync(_socketQueue, block);

    return result;
}

- (NSData *)readDataToLength:(NSUInteger)length
{
    __unsafe_unretained GCDTcpSocket *wself = self;
    __block NSData *result;

    dispatch_block_t block = ^(void) {
        NSRange range = NSMakeRange(0, length);

        result = [wself->_rbuffer subdataWithRange:range];

        [wself->_rbuffer replaceBytesInRange:range
                                   withBytes:NULL
                                      length:0];
    };

    if (dispatch_get_current_queue() == _socketQueue)
        block();
    else
        dispatch_sync(_socketQueue, block);

    return result;
}

- (void)writeData:(NSData *)data
{
    __unsafe_unretained GCDTcpSocket *wself = self;

    dispatch_block_t block = ^(void) {
        [wself->_wbuffer appendData:data];
        dispatch_resume(wself->_wsource);
    };

    if (dispatch_get_current_queue() == _socketQueue)
        block();
    else
        dispatch_sync(_socketQueue, block);
}

@end

@implementation GCDTcpSocket (LineIO)

- (NSRange)rangeOfSeparator:(NSString *)separator
              usingEncoding:(NSStringEncoding)encoding
{
    NSData *separatorData = [separator dataUsingEncoding:encoding];

    NSRange result = [_rbuffer rangeOfData:separatorData
                                   options:0
                                     range:NSMakeRange(0, _rbuffer.length)];

    return result;
}

- (BOOL)canReadLineWithSeparator:(NSString *)separator
                   usingEncoding:(NSStringEncoding)encoding
{
    __unsafe_unretained GCDTcpSocket *wself = self;
    __block BOOL result;

    dispatch_block_t block = ^(void) {
        NSRange range = [wself rangeOfSeparator:separator
                                  usingEncoding:encoding];

        result = range.location != NSNotFound;
    };

    if (dispatch_get_current_queue() == _socketQueue)
        block();
    else
        dispatch_sync(_socketQueue, block);

    return result;
}

- (NSString *)readLineWithSeparator:(NSString *)separator
                      usingEncoding:(NSStringEncoding)encoding
{
    NSRange range = [self rangeOfSeparator:separator
                             usingEncoding:encoding];

    NSUInteger length = range.location + range.length;

    NSData *data = [self readDataToLength:length];

    return [NSString stringWithCString:data.bytes
                              encoding:encoding];
}

- (void)writeLine:(NSString *)line
    withSeparator:(NSString *)separator
    usingEncoding:(NSStringEncoding)encoding
{
    NSString *string = [NSString stringWithFormat:@"%@%@", line, separator];

    NSData *data = [string dataUsingEncoding:encoding];
    
    [self writeData:data];
}

@end
