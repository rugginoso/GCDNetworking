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
#import <netdb.h>

#import "GCDInputStream.h"
#import "GCDOutputStream.h"


@interface GCDTcpSocket ()

@property BOOL connected;

- (void)setupStreamsWithFileDescriptor:(int)fd;

@end

@implementation GCDTcpSocket
{
    dispatch_queue_t _socketQueue;

    GCDInputStream *_inputStream;
    GCDOutputStream *_outputStream;
}

- (id)initWithHost:(NSString *)host port:(uint16_t)port
{
    if (self = [super init]) {
        _host = host;
        _port = port;
        _socketQueue = dispatch_queue_create("GCDNetworking.SocketQueue", DISPATCH_QUEUE_SERIAL);
        _delegateQueue = dispatch_get_main_queue();
    }

    return self;
}

- (id)initWithFileDescriptior:(int)fd
{
    struct sockaddr_storage addr;
    socklen_t len = sizeof(addr);

    if (getpeername(fd, (struct sockaddr *) &addr, &len) < 0)
        return nil;

    char hostname[NI_MAXHOST + 1];
    char portbuf[NI_MAXSERV + 1];
    int ret;
    if ((ret = getnameinfo((struct sockaddr *)&addr, len, hostname, NI_MAXHOST, portbuf, NI_MAXSERV, NI_NUMERICHOST|NI_NUMERICSERV)) != 0) {
        NSLog(@"Error resolving name: %s", gai_strerror(ret));
    }

    NSString *host = [NSString stringWithCString:hostname encoding:NSASCIIStringEncoding];
    uint16_t port = [[NSString stringWithCString:portbuf encoding:NSASCIIStringEncoding] intValue];

    if (self = [self initWithHost:host port:port]) {
        [self setupStreamsWithFileDescriptor:fd];
    }

    return self;
}

- (void)dealloc
{
    if (self.isConnected)
        [self disconnect];

    _host = nil;
}

- (void)connect
{
    __unsafe_unretained GCDTcpSocket *wself = self;

    dispatch_async(wself->_socketQueue, ^(void) {
        // Connect to host
        int fd = -1;

        struct addrinfo *info;
        struct addrinfo hints = {AI_ADDRCONFIG, PF_UNSPEC, SOCK_STREAM, IPPROTO_TCP};
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

        if (connect(fd, info->ai_addr, info->ai_addrlen) < 0) {
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
        freeaddrinfo(info);

        [self setupStreamsWithFileDescriptor:fd];
    });
}

- (void)setupStreamsWithFileDescriptor:(int)fd
{
    __unsafe_unretained GCDTcpSocket *wself = self;

    wself->_inputStream = [[GCDInputStream alloc] initWithFileDescriptor:fd];
    wself->_inputStream.delegateQueue = wself->_delegateQueue;
    wself->_inputStream.readBlock = ^(GCDInputStream *stream, NSUInteger read) {
        if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didReceive:)])
            [wself->_delegate socket:wself didReceive:read];
    };
    wself->_inputStream.closeBlock = ^(GCDInputStream *stream) {
        [wself disconnect];
    };
    wself->_inputStream.errorBlock = ^(GCDInputStream *stream, NSError *error) {
        if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didHaveError:)])
            [wself->_delegate socket:wself didHaveError:error];
    };

    wself->_outputStream = [[GCDOutputStream alloc] initWithFileDescriptor:fd];
    wself->_outputStream.delegateQueue = wself->_delegateQueue;
    wself->_outputStream.writeBlock = ^(GCDOutputStream *stream, NSUInteger wrote) {
        if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didWrite:)])
            [wself->_delegate socket:wself didWrite:wrote];
    };
    wself->_outputStream.errorBlock = ^(GCDOutputStream *stream, NSError *error) {
        if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didHaveError:)])
            [wself->_delegate socket:wself didHaveError:error];
    };

    if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didConnectToHost:port:)]) {
        dispatch_async(wself->_socketQueue, ^(void) {
            [wself->_delegate socket:wself didConnectToHost:wself->_host port:wself->_port];
        });
    }

    [wself->_inputStream open];
    [wself->_outputStream open];

    [wself setConnected:YES];
}

- (void)disconnect
{
    __unsafe_unretained GCDTcpSocket *wself = self;
    dispatch_async(_socketQueue, ^(void) {
        wself->_inputStream = nil;
        wself->_outputStream = nil;

        wself->_socketQueue = nil;

        [wself setConnected:NO];

        if (wself->_delegate && [wself->_delegate respondsToSelector:@selector(socket:didDisconnectFromHost:port:)]) {
            dispatch_async(wself->_delegateQueue, ^(void) {
                [wself->_delegate socket:wself didDisconnectFromHost:wself->_host port:wself->_port];
            });
        }
    });
}

- (NSUInteger)bytesAvaiable
{
    return [_inputStream bytesAvaiable];
}

- (NSData *)readDataToLength:(NSUInteger)length
{
    return [_inputStream dataToLength:length];
}

- (void)writeData:(NSData *)data
{
    [_outputStream writeData:data];
}

@end

@implementation GCDTcpSocket (Blocking)

- (BOOL)waitForConnectionNotifyWithTimeout:(NSTimeInterval)timeout
{
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + timeout;

    do {
        if (self.isConnected)
            return YES;
    } while (CFAbsoluteTimeGetCurrent() <= end);

    return NO;
}

- (BOOL)waitForDisconnecionNotifyWithTimeout:(NSTimeInterval)timeout
{
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + timeout;

    do {
        if (!self.isConnected)
            return YES;
    } while (CFAbsoluteTimeGetCurrent() <= end);

    return NO;
}

- (BOOL)waitForReadNotifyWithTimeout:(NSTimeInterval)timeout
{
    return [_inputStream waitForReadNotifyWithTimeout:timeout];
}

- (BOOL)waitForWriteNotifyWithTimeout:(NSTimeInterval)timeout
{
    return [_outputStream waitForWriteNotifyWithTimeout:timeout];
}

@end

@implementation GCDTcpSocket (LineIO)

- (BOOL)canReadLineWithSeparator:(NSString *)separator
                   usingEncoding:(NSStringEncoding)encoding
{
    return [_inputStream canReadLineWithSeparator:separator
                                    usingEncoding:encoding];
}

- (NSString *)readLineWithSeparator:(NSString *)separator
                      usingEncoding:(NSStringEncoding)encoding
{
    return [_inputStream readLineWithSeparator:separator
                                 usingEncoding:encoding];
}

- (void)writeLine:(NSString *)line
    withSeparator:(NSString *)separator
    usingEncoding:(NSStringEncoding)encoding
{
    [_outputStream writeLine:line
               withSeparator:separator
               usingEncoding:encoding];
}

@end
