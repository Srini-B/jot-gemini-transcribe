// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs a block and turns an Objective-C exception it raises into an NSError.
/// Swift cannot catch NSException; AVFAudio raises one from `installTap` and
/// `prepare` when the input device changes under a graph being built.
@interface VQObjCException : NSObject
+ (BOOL)perform:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(perform(_:));
@end

/// `domain` of the NSError; `userInfo[NSLocalizedDescriptionKey]` is the
/// exception's name and reason.
extern NSErrorDomain const VQObjCExceptionErrorDomain;

NS_ASSUME_NONNULL_END
