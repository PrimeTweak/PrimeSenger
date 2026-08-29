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
//
//   -[LSComposerActionView setAction:animated:]  v28@0:8q16B24
//   ivar _sendButton : UIButton
//
// Two ways of revealing the host's own send button were measured and both
// failed. Writing hidden, enabled and frame back after the host produced a
// flash, since the host wrote again on the next pass. Giving the button a
// subclass that refuses those writes was bypassed outright: the swap lands,
// the status reads pinned, and the view tree still shows the button at 0x0
// and hidden, because the flag is backed by the layer and the host reaches
// it another way.
//
// So the host is no longer fought. The button it shows and sizes while the
// field is empty is the emoji, and that is the one dressed as a send button:
// it takes the send button's image and its target, and loses its title. The
// real send button is left untouched, and the host still brings it up by
// itself once text is typed.

static void PSGDressEmojiAsSend(UIView *view) {
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
    if (emoji == nil) {
        [PRMDebug setStatus:@"emoji absent" forKey:@"quick reaction"];
        return;
    }

    UIImage *glyph = [send imageForState:UIControlStateNormal];
    NSString *title = [emoji titleForState:UIControlStateNormal];

    // Written only where it differs, so a layout pass that changes nothing
    // cannot start another one.
    if (title.length > 0) [emoji setTitle:@"" forState:UIControlStateNormal];
    if (glyph != nil && [emoji imageForState:UIControlStateNormal] != glyph) {
        [emoji setImage:glyph forState:UIControlStateNormal];
    }

    // The tap is routed to whatever the host wired the send button to, so
    // nothing is invented and the send path stays the host's own.
    NSArray<NSString *> *actions =
        [send actionsForTarget:send.allTargets.anyObject
               forControlEvent:UIControlEventTouchUpInside];
    id target = send.allTargets.anyObject;
    if (target != nil && actions.count > 0) {
        SEL action = NSSelectorFromString(actions.firstObject);
        if (![[emoji actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]
                containsObject:actions.firstObject]) {
            [emoji removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
            [emoji addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
        }
    }

    [PRMDebug setStatus:[NSString stringWithFormat:@"emoji %.0fx%.0f%@ | glyph %@ | target %@",
                         emoji.frame.size.width, emoji.frame.size.height,
                         emoji.isHidden ? @" hidden" : @"",
                         glyph ? @"copied" : @"MISSING",
                         target ? NSStringFromClass([target class]) : @"none"]
                 forKey:@"quick reaction"];
}

%hook LSComposerActionView

- (void)setAction:(NSInteger)action animated:(BOOL)animated {
    %orig;
    [PRMDebug noteHook:@"quick reaction"];
    if (![PRMPrefs isEnabled:PRMKeyHideQuickReaction]) return;
    [PRMDebug noteAction:@"quick reaction"];
    PSGDressEmojiAsSend((UIView *)self);
}

// The class does not implement this itself, so the original resolves to the
// superclass. Running after it means the host has already placed everything.
- (void)layoutSubviews {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyHideQuickReaction]) return;
    [PRMDebug noteHook:@"quick reaction layout"];
    [PRMDebug noteAction:@"quick reaction layout"];
    PSGDressEmojiAsSend((UIView *)self);
}

%end
