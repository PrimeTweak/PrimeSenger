// Presents the tweak's settings from anywhere. Kept apart from PRMDebug so
// the shared core does not have to know about the Messenger-specific screen
// at compile time.

#import "PRMDebug.h"
#import "PSGSettings.h"

@implementation PRMDebug (PRMLauncher)

+ (void)openSettings {
    UIWindow *window = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window != nil) break;
    }
    UIViewController *host = window.rootViewController;
    while (host.presentedViewController != nil) host = host.presentedViewController;
    if (host == nil) return;

    [host presentViewController:[PSGSettingsViewController presentable]
                       animated:YES
                     completion:nil];
}

// Requests arrive in bursts on screen and keyboard changes, so they are
// coalesced into one placement once layout and the keyboard have settled.
+ (void)refreshFloatingButton {
    static NSUInteger generation = 0;
    NSUInteger mine = ++generation;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (mine != generation) return;
        [self installButton];
    });
}

@end
