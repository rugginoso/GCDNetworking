//
//  NSError+Errno.h
//  GCDNetworking
//
//  Created by Lorenzo Masini on 12/02/12.
//  Copyright (c) 2012 Develer srl. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSError (Errno)

+ (id)errorWithErrno:(int)e description:(NSString *)description;

@end