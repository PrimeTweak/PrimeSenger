// One probe for four open options. Nothing is corrected here: every fix
// attempt is removed so the readings are not polluted by them.
//
// What is already measured and needs no probe:
//   -[LSComposerViewController _actionButtonWithTextTyped:]  @20@0:8B16
//       fires and was forced, and the emoji stayed. It builds a button, it
//       does not choose the shown one.
//   -[LSComposerActionView setAction:animated:]  v28@0:8q16B24
//       receives 0 while the field is empty and 1 once text is typed.
//   -[LSNetworkImageView layoutSubviews]  v16@0:8
//       the recogniser installs, 32 times, and never fires.
//
// What each section answers is written above it.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma mark - Shared helpers

// Reads a scalar BOOL ivar without messaging the object, so a forward
// declared class is never the receiver. A missing ivar prints as a dash so
// it can never be misread as a NO.
static NSString *PSGFlag(id object, const char *name) {
    if (object == nil || name == NULL) return @"-";
    Ivar slot = class_getInstanceVariable(object_getClass(object), name);
    if (slot == NULL) return @"-";
    const char *bytes = (const char *)(__bridge const void *)object;
    return bytes[ivar_getOffset(slot)] ? @"1" : @"0";
}

static id PSGIvar(id object, const char *name) {
    if (object == nil || name == NULL) return nil;
    Ivar slot = class_getInstanceVariable(object_getClass(object), name);
    return slot ? object_getIvar(object, slot) : nil;
}

static NSString *PSGButtonState(UIButton *button, NSString *label) {
    if (![button isKindOfClass:[UIButton class]]) return [label stringByAppendingString:@":absent"];
    CGRect f = button.frame;
    return [NSString stringWithFormat:@"%@:%@%.0fx%.0f%@%@", label,
            button.isHidden ? @"hidden " : @"",
            f.size.width, f.size.height,
            button.isSelected ? @" sel" : @"",
            button.isEnabled ? @"" : @" off"];
}

// Class names of every recogniser on a view, so an arbitration loss is
// visible rather than guessed.
static NSString *PSGRecognizers(UIView *view) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UIGestureRecognizer *r in view.gestureRecognizers) {
        [names addObject:NSStringFromClass([r class])];
    }
    return names.count ? [names componentsJoinedByString:@","] : @"none";
}

#pragma mark - Presence report

// Answers, without any action from the user, whether every selector this
// tweak depends on exists on this build of Messenger. A hook on a method the
// class does not implement is added by Logos and then never called, which is
// exactly what a zero counter looks like.
%ctor {
    static const char *const classes[] = {
        "LSMediaViewController", "LSMediaVideoViewController",
        "MSGEphemeralMediaViewController", "LSMediaPickerViewController",
        "LSComposerActionView", "LSComposerViewController",
        "LSNetworkImageView", "LSThreadMediaViewerBucketViewController",
        "LSMediaPhotoViewController", "MSGMessageLongPressOverlayViewController"
    };
    static const char *const selectors[] = {
        "markViewOnceMessageAsOpened:", "_didTapHDToggle:", "setAction:animated:",
        "image", "layoutSubviews", "canSaveMedia", "isContentCensored",
        "_actionButtonWithTextTyped:", "viewDidAppear:"
    };

    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    NSMutableArray<NSString *> *viewOnce = [NSMutableArray array];

    for (size_t c = 0; c < sizeof(classes) / sizeof(classes[0]); c++) {
        Class cls = objc_getClass(classes[c]);
        if (cls == Nil) {
            [missing addObject:[NSString stringWithFormat:@"%s:CLASS", classes[c]]];
            continue;
        }
        for (size_t s = 0; s < sizeof(selectors) / sizeof(selectors[0]); s++) {
            SEL sel = sel_registerName(selectors[s]);
            if (class_getInstanceMethod(cls, sel) == NULL) continue;
            if (strcmp(selectors[s], "markViewOnceMessageAsOpened:") == 0) {
                [viewOnce addObject:@(classes[c])];
            }
        }
    }

    [PRMDebug setStatus:missing.count ? [missing componentsJoinedByString:@" "] : @"all classes present"
                 forKey:@"probe classes"];
    [PRMDebug setStatus:viewOnce.count ? [viewOnce componentsJoinedByString:@" "]
                                       : @"markViewOnceMessageAsOpened: on NO class"
                 forKey:@"probe view once"];
}

#pragma mark - Composer action

// Theory to settle: 1 shows the send button and 0 the emoji. Rather than
// trusting the number, both buttons are described after every change, so the
// mapping is read off the geometry instead of inferred from timing.
%hook LSComposerActionView

- (void)setAction:(NSInteger)action animated:(BOOL)animated {
    %orig;
    [PRMDebug noteHook:@"composer action"];

    id view = self;
    UIButton *send = PSGIvar(view, "_sendButton");

    // The emoji lives in the arranged stack rather than in an ivar, so it is
    // found by being a button that is not the send button.
    UIButton *other = nil;
    for (UIView *child in ((UIView *)view).subviews) {
        for (UIView *leaf in child.subviews) {
            if ([leaf isKindOfClass:[UIButton class]] && leaf != send) {
                other = (UIButton *)leaf;
                break;
            }
        }
        if ([child isKindOfClass:[UIButton class]] && child != send) other = (UIButton *)child;
    }

    static NSMutableArray<NSString *> *trace = nil;
    if (trace == nil) trace = [NSMutableArray array];
    [trace addObject:[NSString stringWithFormat:@"[%ld ivar%@ %@ %@ title=%@]",
                      (long)action,
                      PSGFlag(view, "_action"),
                      PSGButtonState(send, @"send"),
                      PSGButtonState(other, @"other"),
                      [other titleForState:UIControlStateNormal] ?: @"-"]];
    while (trace.count > 6) [trace removeObjectAtIndex:0];

    [PRMDebug setStatus:[trace componentsJoinedByString:@" "] forKey:@"composer action"];
}

%end

#pragma mark - Hold to save

// Theory to settle: the host's own long press wins the arbitration. The
// recogniser is installed with a delegate that allows simultaneous
// recognition, and every state transition is recorded. If it now reaches
// Began, simultaneity was the answer. If it never does, the touch never
// reaches this view and the whole approach is wrong.
@interface PSGHoldProbe : UILongPressGestureRecognizer <UIGestureRecognizerDelegate>
@end

@implementation PSGHoldProbe

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

@end

@interface PSGHoldWatcher : NSObject
+ (instancetype)shared;
@end

@implementation PSGHoldWatcher

+ (instancetype)shared {
    static PSGHoldWatcher *watcher = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ watcher = [[PSGHoldWatcher alloc] init]; });
    return watcher;
}

- (void)handleHold:(UIGestureRecognizer *)recognizer {
    static NSMutableArray<NSString *> *trace = nil;
    if (trace == nil) trace = [NSMutableArray array];

    static const char *const names[] = {"possible","began","changed","ended","cancelled","failed"};
    NSInteger state = recognizer.state;
    NSString *label = (state >= 0 && state < 6) ? @(names[state]) : @"?";

    id view = recognizer.view;
    NSString *image = @"-";
    if ([view respondsToSelector:@selector(image)]) {
        UIImage *found = ((id (*)(id, SEL))objc_msgSend)(view, @selector(image));
        image = [found isKindOfClass:[UIImage class]]
              ? [NSString stringWithFormat:@"%.0fx%.0f", found.size.width, found.size.height]
              : @"nil";
    }

    [PRMDebug noteAction:@"hold fired"];
    [trace addObject:[NSString stringWithFormat:@"%@/img=%@", label, image]];
    while (trace.count > 8) [trace removeObjectAtIndex:0];
    [PRMDebug setStatus:[trace componentsJoinedByString:@" "] forKey:@"hold gesture"];
}

@end

%hook LSNetworkImageView

- (void)layoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyHoldToSave]) return;

    UIView *view = (UIView *)self;
    for (UIGestureRecognizer *installed in view.gestureRecognizers) {
        if ([installed isKindOfClass:[PSGHoldProbe class]]) return;
    }

    // Counted once per install, and separately from the gesture firing, so
    // the two numbers can never be confused again.
    [PRMDebug noteHook:@"hold install"];

    // The chain above the view and the recognisers already in place, taken
    // before anything is changed.
    static BOOL described = NO;
    if (!described) {
        described = YES;
        NSMutableArray<NSString *> *chain = [NSMutableArray array];
        UIView *walk = view.superview;
        for (int i = 0; i < 4 && walk != nil; i++) {
            [chain addObject:[NSString stringWithFormat:@"%@(%@)",
                              NSStringFromClass([walk class]), PSGRecognizers(walk)]];
            walk = walk.superview;
        }
        [PRMDebug setStatus:[NSString stringWithFormat:
                             @"%.0fx%.0f uie=%d self=%@ | %@",
                             view.bounds.size.width, view.bounds.size.height,
                             view.userInteractionEnabled, PSGRecognizers(view),
                             [chain componentsJoinedByString:@" < "]]
                     forKey:@"hold context"];
    }

    PSGHoldProbe *hold = [[PSGHoldProbe alloc] initWithTarget:[PSGHoldWatcher shared]
                                                        action:@selector(handleHold:)];
    hold.minimumPressDuration = 0.45;
    hold.cancelsTouchesInView = NO;
    hold.delaysTouchesBegan = NO;
    hold.delegate = hold;

    view.userInteractionEnabled = YES;
    [view addGestureRecognizer:hold];
}

%end

#pragma mark - HD uploads

// Theory to settle: which ivar carries the HD state. Nothing is tapped by
// the tweak. The picker is described on appearance, and the host's own tap
// handler is watched, so one manual tap of the HD control shows exactly
// which value moves.
%hook LSMediaPickerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [PRMDebug noteHook:@"hd appear"];

    id picker = self;
    UIButton *toggle = PSGIvar(picker, "_hdToggleButton");
    UILabel *label = PSGIvar(picker, "_hdToggleLabel");
    UIView *badge = PSGIvar(picker, "_hdBadgeView");

    [PRMDebug setStatus:[NSString stringWithFormat:
                         @"%@ persist=%@ chip=%@ label=%@ badge=%@",
                         PSGButtonState(toggle, @"toggle"),
                         PSGFlag(picker, "_shouldPersistHdToggleState"),
                         PSGFlag(picker, "_enableChipStyledHdToggle"),
                         [label isKindOfClass:[UILabel class]] ? (label.text ?: @"nil") : @"-",
                         badge ? (badge.isHidden ? @"hidden" : @"shown") : @"-"]
                 forKey:@"hd state"];
}

// The ground truth: what one real tap changes.
- (void)_didTapHDToggle:(id)sender {
    id picker = self;
    UIButton *toggle = PSGIvar(picker, "_hdToggleButton");
    NSString *before = PSGButtonState(toggle, @"before");

    %orig;

    [PRMDebug noteHook:@"hd tap"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ -> %@ | sender=%@ | persist=%@",
                         before, PSGButtonState(toggle, @"after"),
                         sender ? NSStringFromClass([sender class]) : @"nil",
                         PSGFlag(picker, "_shouldPersistHdToggleState")]
                 forKey:@"hd tap"];
}

%end
