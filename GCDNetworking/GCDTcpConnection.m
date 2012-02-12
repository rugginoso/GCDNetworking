//
//  GCDTcpConnection.m
//  GCDNetworking
//
//  Created by Lorenzo Masini on 06/02/12.
//  Copyright (c) 2012 Develer srl. All rights reserved.
//

#import "GCDTcpConnection.h"

#import <Foundation/Foundation.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>


@interface GCDTcpConnection ()

@property (readonly, nonatomic) int fd;
@property (readonly, nonatomic) dispatch_source_t readSource;
@property (readonly, nonatomic) dispatch_source_t writeSource;
@property (readonly, nonatomic) NSMutableData *readBuffer;
@property (readonly, nonatomic) NSMutableData *writeBuffer;
@property (readwrite, nonatomic, retain) NSHost *peerHost;
@property (readwrite, nonatomic, assign) uint16_t *peerPort;

@end

@implementation GCDTcpConnection
{
    int fd;

    NSHost *peerHost;
    uint16_t peerPort;

    dispatch_queue_t socketQueue;
    dispatch_source_t readSource;
    dispatch_source_t writeSource;

    NSMutableData *readBuffer;
    NSMutableData *writeBuffer;

    id<GCDTcpConnectionDelegate> delegate;
    dispatch_queue_t delegateQueue;
}

@synthesize peerHost;
@synthesize peerPort;
@synthesize delegate;
@synthesize delegateQueue;

@synthesize fd;
@synthesize readSource;
@synthesize writeSource;
@synthesize readBuffer;
@synthesize writeBuffer;


+ (void)connectToHost:(NSHost *)host
                 port:(uint16_t)port
         withDelegate:(id<GCDTcpConnectionDelegate>) delegate
        delegateQueue:(dispatch_queue_t)queue
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        int fd = -1;
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(struct sockaddr_in));

        const char *hostname = [[host address] cStringUsingEncoding:NSASCIIStringEncoding];

        inet_aton(hostname, &addr.sin_addr);
        addr.sin_port = htons(port);

        if ((fd = socket(PF_INET, SOCK_STREAM, 0)) < 0)
            return;

        if (connect(fd, (struct sockaddr *) &addr, sizeof(struct sockaddr_in)) < 0)
            return;

        GCDTcpConnection *connection = [[GCDTcpConnection alloc] initWithFileDescriptor:fd];
        if (connection) {
            [connection setPeerHost:host];
            [connection setPeerPort:port];

            if (queue)
                [connection setDelegateQueue:queue];

            if (delegate) {
                [connection setDelegate:delegate];
                dispatch_async(connection.delegateQueue, ^(void) {
                    [delegate didConnectWithConnection:[connection autorelease]];
                });
            }
        }
    });
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"GCDTcpConnection (%@:%u)", [peerHost address], peerPort];
}

- (id)initWithFileDescriptor:(int)fileDescriptor
{
    if (fileDescriptor < 0)
        return nil;

    if (self = [super init]) {
        fd = fileDescriptor;

        const char *label = [[NSString stringWithFormat:@"com.Develer.GCDTcpConnection%d", fd]
                             cStringUsingEncoding:NSASCIIStringEncoding];

        socketQueue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL);
        delegateQueue = dispatch_get_main_queue();

        readBuffer = [[NSMutableData alloc] init];
        writeBuffer = [[NSMutableData alloc] init];

        readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                            fd,
                                            0,
                                            socketQueue);

        writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE,
                                             fd,
                                             0,
                                             socketQueue);

        __block GCDTcpConnection *wself = self;

        dispatch_source_set_event_handler(readSource, ^(void) {
            NSUInteger estimated = dispatch_source_get_data([wself readSource]);
            void *buf = malloc(estimated);

            ssize_t got = read([wself fd], buf, estimated);

            [[wself readBuffer] appendBytes:buf length:got];

            if ([wself delegate]) {
                dispatch_async([wself delegateQueue], ^(void) {
                    [[wself delegate] didReceiveDataOnConnection:wself];
                });
            }
            free(buf);
        });

        dispatch_source_set_event_handler(writeSource, ^(void) {
            NSUInteger wrote = write([wself fd],
                                     [[wself writeBuffer] bytes],
                                     [[wself writeBuffer] length]);

            [[wself writeBuffer] replaceBytesInRange:NSMakeRange(0, wrote)
                                           withBytes:NULL
                                              length:0];

            if ([[wself writeBuffer] length] == 0) {
                dispatch_suspend([wself writeSource]);
                if ([wself delegate]) {
                    dispatch_async([wself delegateQueue], ^(void) {
                        [[wself delegate] didFinishWriteOnConnection:wself];
                    });
                }
            }
        });

        dispatch_block_t cancelHandler = ^(void) {
            close(fileDescriptor);
        };

        dispatch_source_set_cancel_handler(readSource, cancelHandler);
        dispatch_source_set_cancel_handler(writeSource, cancelHandler);

        dispatch_resume(readSource);
    }

    return self;
}

- (void)dealloc
{
    [self disconnect];

    dispatch_release(readSource);
    dispatch_release(writeSource);

    dispatch_release(socketQueue);
    dispatch_release(delegateQueue);

    [readBuffer release];
    [writeBuffer release];

    [super dealloc];
}

- (void)disconnect
{
    [peerHost release];
    peerHost = nil;

    peerPort = 0;

    dispatch_source_cancel(readSource);

    // Resume writeSource to correctly call the cancel handler
    dispatch_resume(writeSource);
    dispatch_source_cancel(writeSource);
}

- (NSUInteger)bytesAvaiable
{
    __block GCDTcpConnection *wself = self;
    __block NSUInteger result;

    dispatch_block_t block = ^(void) {
        result = [[wself readBuffer] length];
    };

    if (dispatch_get_current_queue() == socketQueue)
        block();
    else
        dispatch_sync(socketQueue, block);

    return result;
}

- (NSData *)readDataToLength:(NSUInteger)length
{
    __block GCDTcpConnection *wself = self;
    __block NSData *result;

    dispatch_block_t block = ^(void) {
        NSRange range = NSMakeRange(0, length);

        result = [[wself readBuffer] subdataWithRange:range];

        [[wself readBuffer] replaceBytesInRange:range
                                      withBytes:NULL
                                         length:0];
    };

    if (dispatch_get_current_queue() == socketQueue)
        block();
    else
        dispatch_sync(socketQueue, block);

    return result;
}

- (void)writeData:(NSData *)data
{
    __block GCDTcpConnection *wself = self;

    dispatch_block_t block = ^(void) {
        [[wself writeBuffer] appendData:data];
        dispatch_resume([wself writeSource]);
    };

    if (dispatch_get_current_queue() == socketQueue)
        block();
    else
        dispatch_sync(socketQueue, block);
}

@end

@implementation GCDTcpConnection (LineIO)

- (NSRange)rangeOfSeparator:(NSString *)separator
              usingEncoding:(NSStringEncoding)encoding
{
    NSData *separatorData = [separator dataUsingEncoding:encoding];

    NSRange result = [readBuffer rangeOfData:separatorData
                                     options:0
                                       range:NSMakeRange(0, [readBuffer length])];

    return result;
}

- (BOOL)canReadLineWithSeparator:(NSString *)separator
                   usingEncoding:(NSStringEncoding)encoding
{
    __block GCDTcpConnection *wself = self;
    __block BOOL result;

    dispatch_block_t block = ^(void) {
        NSRange range = [wself rangeOfSeparator:separator
                                  usingEncoding:encoding];

        result = range.location != NSNotFound;
    };

    if (dispatch_get_current_queue() == socketQueue)
        block();
    else
        dispatch_sync(socketQueue, block);

    return result;
}

- (NSString *)readLineWithSeparator:(NSString *)separator
                      usingEncoding:(NSStringEncoding)encoding
{
    NSRange range = [self rangeOfSeparator:separator
                             usingEncoding:encoding];

    NSUInteger length = range.location + range.length;

    NSData *data = [self readDataToLength:length];

    return [NSString stringWithCString:[data bytes]
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