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
        [PRMDebug log:@"FLEXManager absent: the vendor clone did not compile in"];
        return;
    }

    id shared = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(sharedManager));
    if (shared == nil) return;

    BOOL hidden = YES;
    if ([shared respondsToSelector:@selector(isHidden)]) {
        hidden = ((BOOL (*)(id, SEL))objc_msgSend)(shared, @selector(isHidden));
    }

    SEL action = hidden ? @selector(showExplorer) : @selector(hideExplorer);
    if (![shared respondsToSelector:action]) {
        [PRMDebug log:@"FLEXManager does not answer %@", NSStringFromSelector(action)];
        return;
    }
    ((void (*)(id, SEL))objc_msgSend)(shared, action);
    [PRMDebug log:@"FLEX %@", hidden ? @"shown" : @"hidden"];
}

@end
