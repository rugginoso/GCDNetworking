//
//  GCDInputStream.h
//  GCDNetworking
//
//  Created by Lorenzo Masini on 01/03/13.
//  Copyright (c) 2013 Develer srl. All rights reserved.
//

#import <Foundation/Foundation.h>

@class GCDInputStream;

typedef void (^GCDInputStreamReadBlock)(GCDInputStream *, NSUInteger);
typedef void (^GCDInputStreamCloseBlock)(GCDInputStream *);
typedef void (^GCDInputStreamErrorBlock)(GCDInputStream *, NSError *);

@interface GCDInputStream : NSObject

@property (strong) dispatch_queue_t delegateQueue;
@property (strong) GCDInputStreamReadBlock readBlock;
@property (strong) GCDInputStreamCloseBlock closeBlock;
@property (strong) GCDInputStreamErrorBlock errorBlock;

- (id)initWithFileDescriptor:(int)fileDescriptor;

- (void)open;
- (void)close;

- (NSUInteger)bytesAvaiable;
- (NSData *)dataToLength:(NSUInteger)length;

@end

@interface GCDInputStream (Blocking)

- (BOOL)waitForReadNotifyWithTimeout:(NSTimeInterval)timeout;

@end

@interface GCDInputStream (LineIO)

- (BOOL)canReadLineWithSeparator:(NSString *)separator
                   usingEncoding:(NSStringEncoding)encoding;

- (NSString *)readLineWithSeparator:(NSString *)separator
                      usingEncoding:(NSStringEncoding)encoding;

@end

@protocol GCDInputStreamDelegate <NSObject>

- (void)stream:(GCDInputStream *)stream didReceive:(NSUInteger)bytes;

- (void)socket:(GCDInputStream *)socket didHaveError:(NSError *)error;

@end