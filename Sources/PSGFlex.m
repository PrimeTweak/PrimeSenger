// fleXD entry point.
//
// The explorer is reached by a long press on the floating button, so the
// short tap keeps opening settings. FLEX is resolved through the runtime
// rather than imported, so this file compiles whether or not vendor/FLEX
// was cloned, and the tweak still runs if the clone failed.
//
// Measured from the fleXD 6.1.0 podspec:
//   FLEXManager  +sharedManager  -showExplorer  -hideExplorer  -isHidden

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation PRMDebug (PSGFlex)

+ (BOOL)flexAvailable {
    return NSClassFromString(@"FLEXManager") != Nil;
}

// Driven by the preference rather than by the explorer's own state. The
// earlier version read isHidden and inverted it, so a relaunch left the
// explorer closed with the switch still on, and turning the switch off
// opened it.
+ (void)applyFlexState {
    Class manager = NSClassFromString(@"FLEXManager");
    if (manager == Nil) {
        [PRMDebug setStatus:@"FLEXManager absent, the vendor clone is not in the dylib"
                     forKey:@"flex"];
        return;
    }

    id shared = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(sharedManager));
    if (shared == nil) {
        [PRMDebug setStatus:@"sharedManager returned nil" forKey:@"flex"];
        return;
    }

    BOOL wanted = ![PRMPrefs isEnabled:PRMKeyMasterDisable]
               && [PRMPrefs isEnabled:PRMKeyFlexEnabled];

    BOOL showing = NO;
    if ([shared respondsToSelector:@selector(isHidden)]) {
        showing = !((BOOL (*)(id, SEL))objc_msgSend)(shared, @selector(isHidden));
    }
    if (wanted == showing) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"already %@",
                             wanted ? @"showing" : @"hidden"]
                     forKey:@"flex"];
        return;
    }

    if (!wanted) {
        if ([shared respondsToSelector:@selector(hideExplorer)]) {
            ((void (*)(id, SEL))objc_msgSend)(shared, @selector(hideExplorer));
        }
        [PRMDebug setStatus:@"hidden" forKey:@"flex"];
        return;
    }

    // The explorer builds its own window, which needs a scene on iOS 15 and
    // later. Without one it can be created without ever being attached.
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (candidate.activationState == UISceneActivationStateForegroundActive
            && [candidate isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }

    if (scene != nil && [shared respondsToSelector:@selector(showExplorerFromScene:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(shared,
                                              @selector(showExplorerFromScene:), scene);
        [PRMDebug setStatus:@"shown from scene" forKey:@"flex"];
        return;
    }

    if ([shared respondsToSelector:@selector(showExplorer)]) {
        ((void (*)(id, SEL))objc_msgSend)(shared, @selector(showExplorer));
        [PRMDebug setStatus:@"shown" forKey:@"flex"];
    }
}

// Kept for the settings row, which asks for the state to be reapplied
// after it has written the preference.
+ (void)toggleFlex {
    [self applyFlexState];
}

@end
