// Keeps the keyboard down when a chat opens. Only the automatic raise is
// suppressed; a tap on the message field still opens it.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGReadReceipts.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Raised while the composer field holds focus, from the two edges the host
// names itself.
static BOOL PSGComposerFocused = NO;

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
    // A fresh composer starts unfocused, whatever the previous thread left.
    PSGComposerFocused = NO;
    [PRMDebug noteHook:@"auto keyboard"];
    if (PSGSuppressAutoKeyboard()) {
        [PRMDebug noteAction:@"auto keyboard"];
        return;
    }
    %orig;
}

// On reply mode: sending a message sends the read receipt through the same
// path the manual eye uses.
- (void)_sendMessageType:(id)type traceId:(id)traceId {
    %orig;
    [PRMDebug noteHook:@"read on reply"];
    if (![PRMPrefs isEnabled:PRMKeyReadOnReply]) return;

    id list = [PSGReadReceipts liveController];
    if (list == nil) {
        [PRMDebug setStatus:@"no thread on screen" forKey:@"read on reply"];
        return;
    }

    [PRMDebug noteAction:@"read on reply"];
    BOOL sent = [PSGReadReceipts sendReceiptOn:list];
    [PRMDebug setStatus:sent ? @"receipt sent" : @"flag unreachable"
                 forKey:@"read on reply"];
}

// Tracks whether the field has focus: the send button is shown while the
// keyboard is up and not once it is gone.
- (void)textViewDidBeginEditing:(id)textView {
    %orig;
    PSGComposerFocused = YES;
    [PRMDebug setStatus:@"focused" forKey:@"composer focus"];
}

- (void)textViewDidEndEditing:(id)textView {
    %orig;
    PSGComposerFocused = NO;
    [PRMDebug setStatus:@"unfocused" forKey:@"composer focus"];
}

// A swipe down dismisses the keyboard without ending editing through the
// delegate, so the host's own resign path is watched as well.
- (void)_resignTextViewFirstResponderIfNeeded {
    %orig;
    PSGComposerFocused = NO;
    [PRMDebug setStatus:@"unfocused by resign" forKey:@"composer focus"];
}

%end

#pragma mark - Quick reaction

// With the field empty the composer shows a one-tap emoji. It is dressed as
// the send button while the keyboard is up, and hidden once it is down.

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
    if (emoji == nil) return;

    // Written only when the line changes: this runs on every layout pass of
    // the action view, and formatting a string each time was measurable.
    static NSString *last = nil;
    NSString *line = nil;

    // With the keyboard gone the slot is left empty: no emoji, and the host's
    // own send button untouched.
    if (!PSGComposerFocused) {
        if (!emoji.isHidden) emoji.hidden = YES;
        line = @"unfocused, emoji hidden";
    } else {
        // The send target first. Dressing the button before the target is
        // known left a button that looked like Send and still sent the emoji
        // whenever the host had not wired its own button yet.
        id target = send.allTargets.anyObject;
        NSArray<NSString *> *actions = target
            ? [send actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]
            : nil;

        if (target == nil || actions.count == 0) {
            if (!emoji.isHidden) emoji.hidden = YES;
            line = @"send target not wired, emoji hidden";
        } else {
            SEL action = NSSelectorFromString(actions.firstObject);
            if (![[emoji actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]
                    containsObject:actions.firstObject]) {
                [emoji removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
                [emoji addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
            }

            UIImage *glyph = [send imageForState:UIControlStateNormal];
            if ([emoji titleForState:UIControlStateNormal].length > 0) {
                [emoji setTitle:@"" forState:UIControlStateNormal];
            }
            if (glyph != nil && [emoji imageForState:UIControlStateNormal] != glyph) {
                [emoji setImage:glyph forState:UIControlStateNormal];
            }
            if (emoji.isHidden) emoji.hidden = NO;

            line = [NSString stringWithFormat:@"dressed | glyph %@ | target %@",
                    glyph ? @"copied" : @"MISSING", NSStringFromClass([target class])];
        }
    }

    if (![line isEqualToString:last]) {
        last = line;
        [PRMDebug setStatus:line forKey:@"quick reaction"];
    }
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

#pragma mark - Read on reaction

// On reply mode: a reaction counts as a reply. The tray pick and the double
// tap to like are watched, since the reaction itself goes through a block.

static void PSGReceiptForReaction(NSString *source) {
    [PRMDebug noteHook:@"read on reaction"];
    if (![PRMPrefs isEnabled:PRMKeyReadOnReply]) return;

    id list = [PSGReadReceipts liveController];
    if (list == nil) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"%@: no thread on screen", source]
                     forKey:@"read on reaction"];
        return;
    }

    [PRMDebug noteAction:@"read on reaction"];
    BOOL sent = [PSGReadReceipts sendReceiptOn:list];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@: %@", source,
                         sent ? @"receipt sent" : @"flag unreachable"]
                 forKey:@"read on reaction"];
}

%hook MSGFacebookReactionView

- (void)didTap {
    %orig;
    PSGReceiptForReaction(@"tray");
}

%end

%hook MSGMessageRowCell

- (void)viewDidDoubleTap:(id)view {
    %orig;
    PSGReceiptForReaction(@"double tap");
}

%end
