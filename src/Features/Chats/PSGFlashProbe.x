// Debug probe for the flash and reorder seen when a thread opens with the
// keyboard kept closed. Records the message list's scroll geometry at a few
// moments after it appears, plus the keyboard frame events around it, so the
// layout settling can be read instead of guessed. Debug builds only.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>

#if PRIMESENGER_DEBUG

static NSTimeInterval gThreadOpenAt = 0.0;

static UIScrollView *PSGFindScroll(UIView *view, NSInteger depth) {
    if (view == nil || depth > 8) return nil;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIScrollView class]]) return (UIScrollView *)sub;
    }
    for (UIView *sub in view.subviews) {
        UIScrollView *found = PSGFindScroll(sub, depth + 1);
        if (found != nil) return found;
    }
    return nil;
}

static void PSGSnapScroll(UIViewController *vc, NSString *tag) {
    UIScrollView *scroll = PSGFindScroll(vc.viewIfLoaded, 0);
    if (scroll == nil) {
        [PRMDebug log:@"flash %@: no scroll view", tag];
        return;
    }
    [PRMDebug log:@"flash %@: offset.y=%.1f inset.bottom=%.1f contentH=%.1f boundsH=%.1f",
              tag, scroll.contentOffset.y, scroll.adjustedContentInset.bottom,
              scroll.contentSize.height, scroll.bounds.size.height];
}

static void PSGArmKeyboardLog(void) {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIKeyboardWillChangeFrameNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) {
            if (![PRMDebug recording] || gThreadOpenAt == 0.0) return;
            NSTimeInterval dt = [NSDate timeIntervalSinceReferenceDate] - gThreadOpenAt;
            if (dt < 0.0 || dt > 4.0) return;
            CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
            [PRMDebug log:@"flash kb @%.0fms: endY=%.0f h=%.0f",
                      dt * 1000.0, end.origin.y, end.size.height];
        }];
    });
}

%hook MSGMessageListViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![PRMDebug recording]) return;

    PSGArmKeyboardLog();
    gThreadOpenAt = [NSDate timeIntervalSinceReferenceDate];

    BOOL closed = [PRMPrefs isEnabled:PRMKeyNoAutoKeyboard];
    [PRMDebug log:@"flash === thread opened, keep-keyboard-closed=%@ ===",
              closed ? @"ON" : @"OFF"];

    UIViewController *vc = (UIViewController *)self;
    PSGSnapScroll(vc, @"t+0");
    NSArray<NSNumber *> *marks = @[@0.3, @0.8, @1.6];
    for (NSNumber *mark in marks) {
        NSString *tag = [NSString stringWithFormat:@"t+%.0fms", mark.doubleValue * 1000.0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(mark.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ PSGSnapScroll(vc, tag); });
    }
}

%end

#endif
