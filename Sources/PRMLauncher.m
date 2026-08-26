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

+ (void)refreshFloatingButton {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self installButton];
    });
}

@end
