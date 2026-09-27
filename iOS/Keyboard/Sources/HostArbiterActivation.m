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

#import "HostArbiterActivation.h"
#import <objc/runtime.h>

// _UIKeyboardArbiterClient only exists in a process when +enabled says so, and
// UIKit asks early. Forcing +enabled to YES from a load-time constructor makes
// the client exist in the keyboard process, where its currentClientState names
// the host app's bundle ID and pid. Installing it later, from viewWillAppear,
// was measured by Dictus to be sometimes too late.

static NSString *const kArbiterClassNameUnderscored = @"_UIKeyboardArbiterClient";
static NSString *const kArbiterClassNamePlain = @"UIKeyboardArbiterClient";
static NSString *const kEnabledSelectorName = @"enabled";

static BOOL gSwizzleInstalled = NO;
static NSString *gLoadTimeOutcome = @"not-attempted";

static Class VIQResolveArbiterClass(void) {
    Class cls = NSClassFromString(kArbiterClassNameUnderscored);
    if (cls == Nil) {
        cls = NSClassFromString(kArbiterClassNamePlain);
    }
    return cls;
}

static NSString *VIQInstallArbiterSwizzle(void) {
    if (gSwizzleInstalled) {
        return @"already";
    }
    Class cls = VIQResolveArbiterClass();
    if (cls == Nil) {
        return @"no-class";
    }
    Method method = class_getClassMethod(cls, NSSelectorFromString(kEnabledSelectorName));
    if (method == NULL) {
        return @"no-method";
    }
    IMP replacement = imp_implementationWithBlock(^BOOL(id _self) {
        return YES;
    });
    method_setImplementation(method, replacement);
    gSwizzleInstalled = YES;
    return @"installed";
}

__attribute__((constructor))
static void VIQActivateArbiterAtLoad(void) {
    gLoadTimeOutcome = VIQInstallArbiterSwizzle();
}

@implementation VIQHostArbiterActivation

+ (NSString *)activate {
    return VIQInstallArbiterSwizzle();
}

+ (NSString *)loadTimeOutcome {
    return gLoadTimeOutcome;
}

@end
