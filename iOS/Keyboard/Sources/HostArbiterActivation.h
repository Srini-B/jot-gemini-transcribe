// Adapted from Dictus (github.com/getdictus/dictus-ios, MIT License,
// Copyright (c) 2026 PIVI Solutions). See THIRD_PARTY_NOTICES.md.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Turns on UIKit's keyboard arbiter client inside the keyboard extension so
/// HostAppResolver can read which app owns the text field. Private API.
@interface VIQHostArbiterActivation : NSObject

/// Installs the swizzle if it is not installed yet. Returns "installed",
/// "already", "no-class" or "no-method".
+ (NSString *)activate;

/// What the load-time attempt returned.
+ (NSString *)loadTimeOutcome;

@end

NS_ASSUME_NONNULL_END
