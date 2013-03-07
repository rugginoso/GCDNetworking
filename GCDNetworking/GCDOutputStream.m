//
//  GCDOutputStream.m
//  GCDNetworking
//
//  Created by Lorenzo Masini on 01/03/13.
//  Copyright (c) 2013 Develer srl. All rights reserved.
//

#import "GCDOutputStream.h"

@interface GCDOutputStream ()
{
    NSMutableData *_buffer;

    dispatch_queue_t _streamQueue;
    dispatch_queue_t _delegateQueue;

    dispatch_source_t _source;
}

@property BOOL writing;

@end


@implementation GCDOutputStream

- (id)initWithFileDescriptor:(int)fileDescriptor
{
    if (self = [super init]) {
        _buffer = [[NSMutableData alloc] init];

        _streamQueue = dispatch_queue_create("GCDNetworking.OutputStreamQueue", DISPATCH_QUEUE_SERIAL);
        _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, fileDescriptor, NULL, _streamQueue);

        _delegateQueue = dispatch_get_main_queue();
    }

    return self;
}

- (void)open
{
    int fileDescriptor = (int)dispatch_source_get_handle(_source);

    __unsafe_unretained GCDOutputStream *wself = self;

    dispatch_source_set_event_handler(wself->_source, ^(void) {
        ssize_t wrote = write(fileDescriptor,
                              wself->_buffer.bytes,
                              wself->_buffer.length);

        dispatch_suspend(wself->_source);
        [wself setWriting:NO];

        if (wrote < 0) {
            if (wself->_errorBlock) {
                dispatch_async(wself->_delegateQueue, ^(void) {
                    wself->_errorBlock(wself, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
                });
            }
            return;
        }

        [wself->_buffer replaceBytesInRange:NSMakeRange(0, wrote)
                                  withBytes:NULL
                                     length:0];

        if (wself->_writeBlock) {
            dispatch_async(wself->_delegateQueue, ^(void) {
                wself->_writeBlock(wself, wrote);
            });
        }
    });

    // Cancel handler
    dispatch_source_set_cancel_handler(wself->_source, ^(void) {
        close(fileDescriptor);
    });
}

- (void)close
{
    if (![self writing])
        dispatch_resume(_source);
    dispatch_source_cancel(_source);
}

- (void)dealloc
{
    [self close];
}

- (void)writeData:(NSData *)data
{
    __unsafe_unretained GCDOutputStream *wself = self;

    dispatch_block_t block = ^(void) {
        [wself->_buffer appendData:data];
        if (![wself writing]) {
            [wself setWriting:YES];
            dispatch_resume(wself->_source);
        }
    };

    if (dispatch_get_current_queue() == _streamQueue)
        block();
    else
        dispatch_async(_streamQueue, block);
}

@end

@implementation GCDOutputStream (Blocking)

- (BOOL)waitForWriteNotifyWithTimeout:(NSTimeInterval)timeout
{
    __unsafe_unretained GCDOutputStream *wself = self;
    __block BOOL result = NO;

    dispatch_block_t block = ^(void) {
        result = wself->_buffer.length == 0;
    };

    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + timeout;

    do {
        if (dispatch_get_current_queue() == _streamQueue)
            block();
        else
            dispatch_sync(_streamQueue, block);

        if (result)
            return YES;

    } while (CFAbsoluteTimeGetCurrent() <= end);
    
    return NO;
}

@end

@implementation GCDOutputStream (LineIO)

- (void)writeLine:(NSString *)line
    withSeparator:(NSString *)separator
    usingEncoding:(NSStringEncoding)encoding
{
    NSString *string = [line stringByAppendingString:separator];
    NSData *data = [string dataUsingEncoding:encoding];
    
    [self writeData:data];
}

@end
