// Keyboard on thread entry.
//
// Messenger raises the keyboard as soon as a conversation opens. The host
// names that path itself, so the automatic raise is suppressed without
// touching the one a tap on the composer triggers.
//
// Signatures taken from the binary:
//   -[LSComposerViewController _autoOpenKeyboardAfterOpenComposerView]         v16@0:8
//   -[LSComposerViewController _scheduleAutoOpenKeyboardAfterOpenComposerView] v16@0:8
//
// Only these two are suppressed. -_makeTextViewFirstResponder and
// -textViewDidBeginEditing: are left alone, so tapping the bar still opens
// the keyboard, and a restored draft still gets focus when the user asks.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL PSGSuppressAutoKeyboard(void) {
    return ![PRMPrefs isEnabled:PRMKeyMasterDisable]
        && [PRMPrefs isEnabled:PRMKeyNoAutoKeyboard];
}

%hook LSComposerViewController

- (void)_autoOpenKeyboardAfterOpenComposerView {
    [PRMDebug noteHook:@"auto keyboard"];
    if (PSGSuppressAutoKeyboard()) {
        [PRMDebug noteAction:@"auto keyboard"];
        return;
    }
    %orig;
}

- (void)_scheduleAutoOpenKeyboardAfterOpenComposerView {
    [PRMDebug noteHook:@"auto keyboard"];
    if (PSGSuppressAutoKeyboard()) {
        [PRMDebug noteAction:@"auto keyboard"];
        return;
    }
    %orig;
}

%end

#pragma mark - Quick reaction

// With the field empty the composer shows an emoji that sends on one tap.
// Measured on LSComposerActionView, which holds both buttons at once:
//
//   [1 ivar1 send:hidden 44x44 off other:44x40 title=..]  field empty
//
// The action value stays at 1 in every sample, so the integer is not what
// decides. What moves is the send button itself: hidden and disabled while
// the emoji stays visible. The two are handled directly.
//
//   -[LSComposerActionView setAction:animated:]  v28@0:8q16B24
//   ivar _sendButton : UIButton
//
// setAction: is a two instruction forward into this method, so every state
// change passes here. The pass is repeated once on the next runloop turn
// because the host lays the view out after this returns.

%hook LSComposerActionView

- (void)setAction:(NSInteger)action animated:(BOOL)animated {
    %orig;
    [PRMDebug noteHook:@"quick reaction"];
    if (![PRMPrefs isEnabled:PRMKeyHideQuickReaction]) return;

    id view = self;
    Ivar slot = class_getInstanceVariable(object_getClass(view), "_sendButton");
    UIButton *send = slot ? object_getIvar(view, slot) : nil;
    if (![send isKindOfClass:[UIButton class]]) {
        [PRMDebug setStatus:@"send button missing" forKey:@"quick reaction"];
        return;
    }

    // The emoji is an arranged child of the stack rather than an ivar, so it
    // is found by being a button that is not the send button.
    UIButton *emoji = nil;
    for (UIView *child in ((UIView *)view).subviews) {
        if ([child isKindOfClass:[UIButton class]] && child != send) emoji = (UIButton *)child;
        for (UIView *leaf in child.subviews) {
            if ([leaf isKindOfClass:[UIButton class]] && leaf != send) emoji = (UIButton *)leaf;
        }
    }

    [PRMDebug noteAction:@"quick reaction"];
    void (^apply)(void) = ^{
        emoji.hidden = YES;
        send.hidden = NO;
        send.enabled = YES;
        // The send button is a sibling of the stack, not an arranged child,
        // so it carries no intrinsic width once the host has collapsed it.
        if (CGRectIsEmpty(send.frame)) send.frame = ((UIView *)view).bounds;
    };
    apply();

    __weak id pending = view;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (pending == nil) return;
        apply();
        [PRMDebug setStatus:[NSString stringWithFormat:
                             @"send %.0fx%.0f%@ emoji %@",
                             send.frame.size.width, send.frame.size.height,
                             send.isHidden ? @" hidden" : @"",
                             emoji.isHidden ? @"hidden" : @"VISIBLE"]
                     forKey:@"quick reaction"];
    });
}

%end
