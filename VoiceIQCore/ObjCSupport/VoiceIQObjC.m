// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

#import "VoiceIQObjC.h"

NSErrorDomain const VQObjCExceptionErrorDomain = @"io.blue.voiceiq.objc-exception";

@implementation VQObjCException
+ (BOOL)perform:(NS_NOESCAPE void (^)(void))block error:(NSError **)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *reason = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @"no reason"];
            *error = [NSError errorWithDomain:VQObjCExceptionErrorDomain code:1
                                     userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return NO;
    }
}
@end
