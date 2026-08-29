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
// decides. What moves is the send button itself: hidden, disabled and sized
// to zero while the emoji stays visible.
//
//   -[LSComposerActionView setAction:animated:]  v28@0:8q16B24
//   ivar _sendButton : UIButton
//
// Writing the properties back after the host wrote them produced a fight:
// the button flashed on while text was typed and went away again on every
// layout pass. The host is not undone after the fact any more. Its own send
// button is given a subclass that refuses to be hidden, disabled or sized to
// nothing, so the host's writes land on a receiver that ignores them.

@interface PSGPersistentSendButton : UIButton
@end

@implementation PSGPersistentSendButton

- (void)setHidden:(BOOL)hidden {
    [super setHidden:NO];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:YES];
}

// The button is a sibling of the stack rather than one of its arranged
// children, so the host collapses it to zero instead of laying it out. An
// empty rect is replaced by the parent's, which keeps it the size of the
// slot it sits in whatever that slot becomes.
- (void)setFrame:(CGRect)frame {
    if (CGRectIsEmpty(frame)) {
        UIView *parent = self.superview;
        if (parent != nil && !CGRectIsEmpty(parent.bounds)) frame = parent.bounds;
    }
    [super setFrame:frame];
}

@end

static void PSGShowSendButton(UIView *view) {
    Ivar slot = class_getInstanceVariable(object_getClass(view), "_sendButton");
    UIButton *send = slot ? object_getIvar(view, slot) : nil;
    if (![send isKindOfClass:[UIButton class]]) return;

    // Swapped once, and only when the button is still the plain class it was
    // measured as. Anything else is left alone rather than guessed at.
    if (object_getClass(send) == [UIButton class]) {
        object_setClass(send, [PSGPersistentSendButton class]);
        send.hidden = NO;
        send.enabled = YES;
        if (CGRectIsEmpty(send.frame)) send.frame = view.bounds;
    }

    // The emoji is an arranged child of the stack rather than an ivar, so it
    // is found by being a button that is not the send button.
    UIButton *emoji = nil;
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:[UIButton class]] && child != send) emoji = (UIButton *)child;
        for (UIView *leaf in child.subviews) {
            if ([leaf isKindOfClass:[UIButton class]] && leaf != send) emoji = (UIButton *)leaf;
        }
    }
    if (emoji != nil && !emoji.isHidden) emoji.hidden = YES;

    [PRMDebug setStatus:[NSString stringWithFormat:@"send %.0fx%.0f%@ %@ | emoji %@",
                         send.frame.size.width, send.frame.size.height,
                         send.isHidden ? @" hidden" : @"",
                         object_getClass(send) == [PSGPersistentSendButton class] ? @"pinned" : @"PLAIN",
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
