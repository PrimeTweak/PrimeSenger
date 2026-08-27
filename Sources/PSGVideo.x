// Video media. LSMediaVideoViewController is a separate class from
// LSMediaViewController and carries its own copy of every permission gate,
// so the media switch has to cover both. The gate bodies are shared.
//
// Signatures taken from the host binary and the runtime scan:
//   -[LSMediaVideoViewController viewDidAppear:]                     v20@0:8B16
//   -[LSMediaVideoViewController playDidEnd]                         v16@0:8
//   -[LSMediaVideoViewController playFromBeginningWhenPossible]      v16@0:8
//   -[LSMediaVideoViewController mediaVideoControlsViewDidTapPlay:]  v24@0:8@16
//   -[LSMediaVideoViewController mediaVideoControlsView:didToggleLoop:]  v28@0:8@16B24
//   ivars _hasPermissionToPlay, _isReadyToPlay, _isPlaying           B

#import "PSGMedia.h"
#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <objc/message.h>
#import <objc/runtime.h>

#pragma mark - Playback state

// The three flags the restart path reads, printed as perm/ready/playing. A
// flag the class does not carry prints as a dash, so a renamed ivar cannot
// be misread as a zero.
static NSString *PSGPlaybackFlags(id controller) {
    static const char *const names[] = {
        "_hasPermissionToPlay", "_isReadyToPlay", "_isPlaying"
    };
    if (controller == nil) return @"-/-/-";

    Class cls = object_getClass(controller);
    const char *bytes = (const char *)(__bridge const void *)controller;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        Ivar ivar = class_getInstanceVariable(cls, names[i]);
        [parts addObject:(ivar == NULL) ? @"-"
                                        : (bytes[ivar_getOffset(ivar)] ? @"1" : @"0")];
    }
    return [parts componentsJoinedByString:@"/"];
}

%hook LSMediaVideoViewController

#pragma mark - Permission gates

- (BOOL)canSaveMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canSave");
}

- (BOOL)canShareMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canShare");
}

- (BOOL)canForwardMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canForward");
}

- (BOOL)canCopyMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canCopy");
}

- (BOOL)canEditMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canEdit");
}

- (BOOL)canReplyMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canReply");
}

- (BOOL)canGetInfo {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canGetInfo");
}

- (BOOL)canShowLiveText {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canLiveText");
}

- (BOOL)canMediaAddToStory {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canAddToStory");
}

- (BOOL)canMediaAddToSharedAlbum {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canAddToAlbum");
}

- (BOOL)canOpenUnifiedShareSheet {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"video canShareSheet");
}

- (BOOL)isContentCensored {
    BOOL original = %orig;
    return PSGCensorGate(original, @"video censored");
}

#pragma mark - Looping

// The host has its own loop switch, reached through the controls view
// delegate. Arming it once per appearance leaves the replay to Messenger
// instead of driving it from the end of playback.
//
// Measured in the host binary: the implementation discards the view it is
// handed and reads its own ivar, so nil is what that argument is worth.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [PRMDebug noteHook:@"video appeared"];
    if (![PRMPrefs isEnabled:PRMKeyLoopVideos]) return;

    id controller = self;
    SEL toggle = @selector(mediaVideoControlsView:didToggleLoop:);
    if (![controller respondsToSelector:toggle]) {
        [PRMDebug setStatus:@"toggle selector missing" forKey:@"video loop"];
        return;
    }

    [PRMDebug noteAction:@"video appeared"];
    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(controller, toggle, nil, YES);
    [PRMDebug setStatus:@"armed at appear" forKey:@"video loop"];
}

// Kept as a second attempt and as the measurement point. The play tap was
// measured being sent and restarting nothing, so the three playback flags
// are read around it: at the end of play, after the host's own bookkeeping,
// and after the tap. Whichever one refuses the restart shows up here.
- (void)playDidEnd {
    [PRMDebug noteHook:@"video playDidEnd"];

    id controller = self;
    NSString *atEnd = PSGPlaybackFlags(controller);
    %orig;
    NSString *afterOriginal = PSGPlaybackFlags(controller);

    if (![PRMPrefs isEnabled:PRMKeyLoopVideos]) {
        [PRMDebug setStatus:[NSString stringWithFormat:
                             @"perm/ready/playing %@ at end, %@ after orig, loop off",
                             atEnd, afterOriginal]
                     forKey:@"video state"];
        return;
    }

    SEL play = @selector(mediaVideoControlsViewDidTapPlay:);
    if (![controller respondsToSelector:play]) {
        [PRMDebug setStatus:@"play tap selector missing" forKey:@"video state"];
        return;
    }

    [PRMDebug noteAction:@"video playDidEnd"];
    ((void (*)(id, SEL, id))objc_msgSend)(controller, play, nil);

    [PRMDebug setStatus:[NSString stringWithFormat:
                         @"perm/ready/playing %@ at end, %@ after orig, %@ after tap",
                         atEnd, afterOriginal, PSGPlaybackFlags(controller)]
                 forKey:@"video state"];
}

%end
