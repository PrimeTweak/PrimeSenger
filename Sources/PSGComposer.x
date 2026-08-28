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
// the emoji stays visible.
//
//   -[LSComposerActionView setAction:animated:]  v28@0:8q16B24
//   ivar _sendButton : UIButton
//
// setAction: is a two instruction forward into this method, so every state
// change passes here. That alone was not enough: it only fires on a
// transition, so a composer built straight into the emoji state never
// reached it, and a later layout pass put the emoji back. The pass is
// therefore repeated from layoutSubviews, which the host runs on creation
// and on every relayout.

static void PSGShowSendButton(UIView *view) {
    Ivar slot = class_getInstanceVariable(object_getClass(view), "_sendButton");
    UIButton *send = slot ? object_getIvar(view, slot) : nil;
    if (![send isKindOfClass:[UIButton class]]) return;

    // The emoji is an arranged child of the stack rather than an ivar, so it
    // is found by being a button that is not the send button.
    UIButton *emoji = nil;
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:[UIButton class]] && child != send) emoji = (UIButton *)child;
        for (UIView *leaf in child.subviews) {
            if ([leaf isKindOfClass:[UIButton class]] && leaf != send) emoji = (UIButton *)leaf;
        }
    }

    // Written only where it differs, so a layout pass that changes nothing
    // cannot start another one.
    if (emoji != nil && !emoji.isHidden) emoji.hidden = YES;
    if (send.isHidden) send.hidden = NO;
    if (!send.isEnabled) send.enabled = YES;
    // The send button is a sibling of the stack, not an arranged child, so it
    // carries no width of its own once the host has collapsed it.
    if (CGRectIsEmpty(send.frame) && !CGRectIsEmpty(view.bounds)) send.frame = view.bounds;

    [PRMDebug setStatus:[NSString stringWithFormat:@"send %.0fx%.0f%@ emoji %@",
                         send.frame.size.width, send.frame.size.height,
                         send.isHidden ? @" hidden" : @"",
                         emoji == nil ? @"absent" : (emoji.isHidden ? @"hidden" : @"VISIBLE")]
                 forKey:@"quick reaction"];
}

%hook LSComposerActionView

- (void)setAction:(NSInteger)action animated:(BOOL)animated {
    %orig;
    [PRMDebug noteHook:@"quick reaction"];
    if (![PRMPrefs isEnabled:PRMKeyHideQuickReaction]) return;
    [PRMDebug noteAction:@"quick reaction"];
    PSGShowSendButton((UIView *)self);
}

// The class does not implement this itself, so the original resolves to the
// superclass. Running after it means the host has already placed everything.
- (void)layoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyHideQuickReaction]) return;
    [PRMDebug noteHook:@"quick reaction layout"];
    PSGShowSendButton((UIView *)self);
}

%end
