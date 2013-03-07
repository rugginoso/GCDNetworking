//
//  GCDOutputStream.h
//  GCDNetworking
//
//  Created by Lorenzo Masini on 01/03/13.
//  Copyright (c) 2013 Develer srl. All rights reserved.
//

#import <Foundation/Foundation.h>

@class GCDOutputStream;

typedef void (^GCDOutputStreamWriteBlock)(GCDOutputStream *, NSUInteger);
typedef void (^GCDOutputStreamErrorBlock)(GCDOutputStream *, NSError *);

@interface GCDOutputStream : NSObject

@property (strong) dispatch_queue_t delegateQueue;
@property (strong) GCDOutputStreamWriteBlock writeBlock;
@property (strong) GCDOutputStreamErrorBlock errorBlock;


- (id)initWithFileDescriptor:(int)fileDescriptor;

- (void)open;
- (void)close;

- (void)writeData:(NSData *)data;

@end

@interface GCDOutputStream (Blocking)

- (BOOL)waitForWriteNotifyWithTimeout:(NSTimeInterval)timeout;

@end

@interface GCDOutputStream (LineIO)

- (void)writeLine:(NSString *)line
    withSeparator:(NSString *)separator
    usingEncoding:(NSStringEncoding)encoding;

@end
