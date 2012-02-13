//
//  NSError+Errno.m
//  GCDNetworking
//
//  Created by Lorenzo Masini on 12/02/12.
//  Copyright (c) 2012 Develer srl. All rights reserved.
//

#import "NSError+Errno.h"

@implementation NSError (Errno)

+ (id)errorWithErrno:(int)e description:(NSString *)description
{
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          NSLocalizedDescriptionKey, description,
                          NSStringEncodingErrorKey, [NSNumber numberWithUnsignedLong:NSUTF8StringEncoding],
                          NSLocalizedFailureReasonErrorKey, [NSString stringWithCString:strerror(e) encoding:NSUTF8StringEncoding],
                          nil];

    return [NSError errorWithDomain:NSPOSIXErrorDomain code:e userInfo:info];
}

@end