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

// With the text field empty, the composer swaps the send button for an emoji
// that fires on a single tap. The host builds that button itself and decides
// which shape to use from the flag it is handed:
//
//   -[LSComposerViewController _actionButtonWithTextTyped:]  @20@0:8B16
//
// Telling it text was typed makes it build the send button in every case.
// Nothing is hidden by force and no geometry is touched: the host lays out
// whatever it built.

%hook LSComposerViewController

- (id)_actionButtonWithTextTyped:(BOOL)textTyped {
    [PRMDebug noteHook:@"quick reaction"];
    if (![PRMPrefs isEnabled:PRMKeyHideQuickReaction]) return %orig;

    [PRMDebug noteAction:@"quick reaction"];
    id button = %orig(YES);
    return button;
}

%end

#pragma mark - Composer action probe

// LSComposerActionView holds both buttons and shows one, chosen by an
// integer. setAction: is a two instruction forward into this method, so
// every change passes here.
//
//   -[LSComposerActionView setAction:animated:]  v28@0:8q16B24
//   ivar _action : q
//
// The values are not named anywhere in the binary. This records them in
// order, so one reading says which integer means send and which means emoji.

%hook LSComposerActionView

- (void)setAction:(NSInteger)action animated:(BOOL)animated {
    %orig;
    [PRMDebug noteHook:@"composer action"];

    static NSMutableArray<NSString *> *trace = nil;
    if (trace == nil) trace = [NSMutableArray array];

    [trace addObject:[NSString stringWithFormat:@"%ld%@", (long)action, animated ? @"a" : @""]];
    while (trace.count > 12) [trace removeObjectAtIndex:0];

    [PRMDebug setStatus:[trace componentsJoinedByString:@" "] forKey:@"composer action"];
}

%end
