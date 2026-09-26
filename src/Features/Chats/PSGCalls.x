// Asks before a call starts. The alert replays the tap through the runtime,
// since the original cannot be invoked from inside its completion block.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <objc/message.h>

static BOOL gCallConfirmed = NO;

%hook LSRTCCallButton

- (void)handleButtonTap {
    [PRMDebug noteHook:@"call button"];

    if (gCallConfirmed || ![PRMPrefs isEnabled:PRMKeyCallConfirmation]) {
        gCallConfirmed = NO;
        %orig;
        return;
    }

    [PRMDebug noteAction:@"call button"];
    __weak id target = self;

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Start call?"
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Call"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        id button = target;
        if (button == nil || ![button respondsToSelector:@selector(handleButtonTap)]) return;
        gCallConfirmed = YES;
        ((void (*)(id, SEL))objc_msgSend)(button, @selector(handleButtonTap));
    }]];

    UIViewController *presenter = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { presenter = window.rootViewController; break; }
        }
        if (presenter != nil) break;
    }
    while (presenter.presentedViewController != nil) {
        presenter = presenter.presentedViewController;
    }
    if (presenter == nil) {
        gCallConfirmed = NO;
        %orig;
        return;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

%end
