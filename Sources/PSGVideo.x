// Video media. LSMediaVideoViewController is a separate class from
// LSMediaViewController and carries its own permission gates, so the media
// switch has to cover both.
// Signatures taken from the binary:
//   -[LSMediaVideoViewController canSaveMedia]     B16@0:8
//   -[LSMediaVideoViewController canShareMedia]    B16@0:8
//   -[LSMediaVideoViewController canForwardMedia]  B16@0:8
//   -[LSMediaVideoViewController canCopyMedia]     B16@0:8
//   -[LSMediaVideoViewController playDidEnd]       v16@0:8
//   -[LSMediaVideoViewController playFromBeginningWhenPossible]  v16@0:8

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <objc/message.h>

%hook LSMediaVideoViewController

- (BOOL)canSaveMedia {
    [PRMDebug noteHook:@"video canSave"];
    BOOL original = %orig;
    if (!original && [PRMPrefs isEnabled:PRMKeyUnlockMedia]) {
        [PRMDebug noteAction:@"video canSave"];
        return YES;
    }
    return original;
}

- (BOOL)canShareMedia {
    [PRMDebug noteHook:@"video canShare"];
    BOOL original = %orig;
    if (!original && [PRMPrefs isEnabled:PRMKeyUnlockMedia]) {
        [PRMDebug noteAction:@"video canShare"];
        return YES;
    }
    return original;
}

- (BOOL)canForwardMedia {
    [PRMDebug noteHook:@"video canForward"];
    BOOL original = %orig;
    if (!original && [PRMPrefs isEnabled:PRMKeyUnlockMedia]) {
        [PRMDebug noteAction:@"video canForward"];
        return YES;
    }
    return original;
}

- (BOOL)canCopyMedia {
    [PRMDebug noteHook:@"video canCopy"];
    BOOL original = %orig;
    if (!original && [PRMPrefs isEnabled:PRMKeyUnlockMedia]) {
        [PRMDebug noteAction:@"video canCopy"];
        return YES;
    }
    return original;
}

// Playback restarts instead of stopping. The original is still called so
// the controller's own end-of-play bookkeeping runs.
- (void)playDidEnd {
    [PRMDebug noteHook:@"video playDidEnd"];
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyLoopVideos]) return;
    [PRMDebug noteAction:@"video playDidEnd"];
    // The class is not declared in any header, so the selector is sent
    // through the runtime rather than messaged directly.
    id controller = self;
    ((void (*)(id, SEL))objc_msgSend)(controller, @selector(playFromBeginningWhenPossible));
}

%end
