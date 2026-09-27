// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
