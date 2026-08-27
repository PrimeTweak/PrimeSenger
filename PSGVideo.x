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
//   -[LSMediaVideoViewController mediaVideoControlsViewDidTapPlay:]  v24@0:8@16

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
//
// The restart is driven by the play tap the controls view sends, not by
// playFromBeginningWhenPossible. That one was measured running once and
// restarting nothing: the controller refuses it after playback has ended.
// The tap goes through the host's own start path, which restores the state
// the restart was waiting on.
- (void)playDidEnd {
    [PRMDebug noteHook:@"video playDidEnd"];
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyLoopVideos]) return;

    // The class is not declared in any header, so self is held as id and
    // every selector is sent through the runtime.
    id controller = self;
    SEL play = @selector(mediaVideoControlsViewDidTapPlay:);
    if (![controller respondsToSelector:play]) {
        [PRMDebug log:@"play tap selector missing on the media video controller"];
        return;
    }

    // Counted after the guard, so the action count is a count of taps sent.
    [PRMDebug noteAction:@"video playDidEnd"];
    ((void (*)(id, SEL, id))objc_msgSend)(controller, play, nil);
}

%end
