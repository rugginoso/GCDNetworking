//
//  GCDInputStream.m
//  GCDNetworking
//
//  Created by Lorenzo Masini on 01/03/13.
//  Copyright (c) 2013 Develer srl. All rights reserved.
//

#import "GCDInputStream.h"

@interface GCDInputStream ()
{
    NSMutableData *_buffer;

    dispatch_queue_t _streamQueue;
    dispatch_queue_t _delegateQueue;

    dispatch_source_t _source;
}
@end

@implementation GCDInputStream

- (id)initWithFileDescriptor:(int)fileDescriptor
{
    if (self = [super init]) {
        _buffer = [[NSMutableData alloc] init];

        _streamQueue = dispatch_queue_create("GCDNetworking.InputStreamQueue", DISPATCH_QUEUE_SERIAL);
        _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fileDescriptor, NULL, _streamQueue);

        _delegateQueue = dispatch_get_main_queue();
    }
    return self;
}

- (void)open
{
    int fileDescriptor = (int)dispatch_source_get_handle(_source);

    __unsafe_unretained GCDInputStream *wself = self;

    dispatch_source_set_event_handler(wself->_source, ^(void) {
        void *buf = NULL;
        NSUInteger estimated = dispatch_source_get_data(wself->_source);
        ssize_t got = 0;

        if (estimated > 0) {
            buf = malloc(estimated);
            got = read(fileDescriptor, buf, estimated);
        }

        if (got == 0) {
            // EOF
            [self close];
            if (wself->_closeBlock) {
                dispatch_async(wself->_delegateQueue, ^(void) {
                    wself->_closeBlock(wself);
                });
            }
            return;
        }

        if (got < 0) { // Error
            if (wself->_errorBlock) {
                dispatch_async(wself->_delegateQueue, ^(void) {
                    wself->_errorBlock(wself, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
                });
            }
            return;
        }

        [wself->_buffer appendBytes:buf length:got];
        free(buf);

        if (wself->_readBlock) {
            dispatch_async(wself->_delegateQueue, ^(void) {
                wself->_readBlock(wself, got);
            });
        }
    });

    // Cancel handler
    dispatch_source_set_cancel_handler(wself->_source, ^(void) {
        close(fileDescriptor);
    });

    dispatch_resume(_source);
}

- (void)close
{
    dispatch_source_cancel(_source);
}

- (void)dealloc
{
    [self close];
}

- (NSUInteger)bytesAvaiable
{
    __unsafe_unretained GCDInputStream *wself = self;
    __block NSUInteger result;

    dispatch_block_t block = ^(void) {
        result = wself->_buffer.length;
    };

    if (dispatch_get_current_queue() == _streamQueue)
        block();
    else
        dispatch_sync(_streamQueue, block);

    return result;
}

- (NSData *)dataToLength:(NSUInteger)length
{
    __unsafe_unretained GCDInputStream *wself = self;
    __block NSData *result;

    dispatch_block_t block = ^(void) {
        NSRange range = NSMakeRange(0, length);

        result = [wself->_buffer subdataWithRange:range];

        [wself->_buffer replaceBytesInRange:range
                                  withBytes:NULL
                                     length:0];
    };

    if (dispatch_get_current_queue() == _streamQueue)
        block();
    else
        dispatch_sync(_streamQueue, block);

    return result;
}

@end

@implementation GCDInputStream (Blocking)

- (BOOL)waitForReadNotifyWithTimeout:(NSTimeInterval)timeout
{
    __unsafe_unretained GCDInputStream *wself = self;
    __block BOOL result = NO;

    dispatch_block_t block = ^(void) {
        result = wself->_buffer.length > 0;
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

@implementation GCDInputStream (LineIO)

- (NSRange)rangeOfSeparator:(NSString *)separator
              usingEncoding:(NSStringEncoding)encoding
{
    NSData *separatorData = [separator dataUsingEncoding:encoding];

    NSRange result = [_buffer rangeOfData:separatorData
                                  options:0
                                    range:NSMakeRange(0, _buffer.length)];

    return result;
}

- (BOOL)canReadLineWithSeparator:(NSString *)separator
                   usingEncoding:(NSStringEncoding)encoding
{
    __unsafe_unretained GCDInputStream *wself = self;
    __block BOOL result;

    dispatch_block_t block = ^(void) {
        NSRange range = [wself rangeOfSeparator:separator
                                  usingEncoding:encoding];

        result = range.location != NSNotFound;
    };

    if (dispatch_get_current_queue() == _streamQueue)
        block();
    else
        dispatch_sync(_streamQueue, block);

    return result;
}

- (NSString *)readLineWithSeparator:(NSString *)separator
                      usingEncoding:(NSStringEncoding)encoding
{
    NSRange range = [self rangeOfSeparator:separator
                             usingEncoding:encoding];

    NSUInteger length = range.location + range.length;
    
    NSData *data = [self dataToLength:length];

    return [[NSString alloc] initWithData:data encoding:encoding];
}

@end
