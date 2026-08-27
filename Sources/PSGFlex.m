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

+ (void)toggleFlex {
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

    BOOL hidden = YES;
    if ([shared respondsToSelector:@selector(isHidden)]) {
        hidden = ((BOOL (*)(id, SEL))objc_msgSend)(shared, @selector(isHidden));
    }

    if (!hidden) {
        if ([shared respondsToSelector:@selector(hideExplorer)]) {
            ((void (*)(id, SEL))objc_msgSend)(shared, @selector(hideExplorer));
            [PRMDebug setStatus:@"hidden" forKey:@"flex"];
        }
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
        [PRMDebug setStatus:[NSString stringWithFormat:@"shown from scene %@",
                             NSStringFromClass([scene class])]
                     forKey:@"flex"];
        return;
    }

    if (![shared respondsToSelector:@selector(showExplorer)]) {
        [PRMDebug setStatus:@"neither showExplorer nor showExplorerFromScene:"
                     forKey:@"flex"];
        return;
    }
    ((void (*)(id, SEL))objc_msgSend)(shared, @selector(showExplorer));
    [PRMDebug setStatus:[NSString stringWithFormat:@"shown, scene %@",
                         scene ? @"present but unused" : @"NONE FOUND"]
                 forKey:@"flex"];
}

@end
