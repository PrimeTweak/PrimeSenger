// Screen tracking. Every controller that appears is recorded once, with a
// full view tree, so no screen has to be captured by hand and no build is
// spent asking what a screen contains.

#import "PRMDebug.h"
#import "PRMPrefs.h"
#import "PRMSuppress.h"

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyDebugEnabled]) return;

    NSString *name = NSStringFromClass([self class]);
    // Skip the tweak's own screens and plain UIKit containers, which would
    // otherwise bury the application's screens in noise.
    if ([name hasPrefix:@"PSG"] || [name hasPrefix:@"PRM"]) return;
    if ([name isEqualToString:@"UINavigationController"]) return;
    if ([name isEqualToString:@"UITabBarController"]) return;
    if ([name isEqualToString:@"UIInputWindowController"]) return;

    [PRMDebug noteScreen:name view:self.viewIfLoaded];
}

// The Meta AI floating button is a Swift controller, so it is matched by
// name here rather than hooked directly: NSStringFromClass reports
// "MSGMetaAIFAB.MSGMetaAIFABViewController" and the mangled runtime name
// would have to be reconstructed by hand.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    NSString *name = NSStringFromClass([self class]);
    if ([PRMSuppress keyForControllerName:name] == nil) return;

    [PRMDebug noteHook:@"suppressed controller"];

    // The host's floating button has just been laid out, so this is the
    // earliest point at which the tweak's own can be placed against it.
    if ([name rangeOfString:@"MetaAIFAB"].location != NSNotFound) {
        [PRMDebug refreshFloatingButton];
    }

    UIView *view = self.viewIfLoaded;
    if (view == nil) return;

    // Assigned rather than forced on: hiding a reused controller's view is
    // otherwise permanent, and switching the preference back off would not
    // restore it until the controller was rebuilt.
    BOOL suppress = [PRMSuppress shouldSuppressControllerName:name];
    if (view.hidden == suppress) return;
    view.hidden = suppress;

    if (suppress) [PRMDebug noteAction:@"suppressed controller"];
    [PRMDebug log:@"%@ controller %@", suppress ? @"hid" : @"restored", name];
}

%end
