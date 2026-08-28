// Video media. LSMediaVideoViewController is a separate class from
// LSMediaViewController and carries its own copy of every permission gate,
// so the media switch has to cover both. The gate bodies are shared.
//
// Signatures taken from the host binary and the runtime scan:
//   -[LSMediaVideoViewController viewDidAppear:]                     v20@0:8B16
//   -[LSMediaVideoViewController playDidEnd]                         v16@0:8
//   -[LSMediaVideoViewController playFromBeginningWhenPossible]      v16@0:8
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

// Measured on the end of a video: the flags read 1/1/0 at the end and the
// original leaves them there. The play tap then took the permission from 1
// to 0 -- the host still believes playback is running, so the tap pauses
// rather than restarts, and it was clearing the permission the loop toggle
// had just been armed with. The tap is gone.
//
// playFromBeginningWhenPossible is not put back in its place: it was the
// first thing tried here and it restarted nothing at those same flags.
//
// What is left is the host's own loop, armed at appearance, with nothing
// interfering. This method now only measures: the flags at the end, after
// the original, and again shortly after, which is where a working loop
// would show playing back at 1.
- (void)playDidEnd {
    [PRMDebug noteHook:@"video playDidEnd"];

    id controller = self;
    NSString *atEnd = PSGPlaybackFlags(controller);
    %orig;
    NSString *afterOriginal = PSGPlaybackFlags(controller);

    [PRMDebug setStatus:[NSString stringWithFormat:
                         @"perm/ready/playing %@ at end, %@ after orig%@",
                         atEnd, afterOriginal,
                         [PRMPrefs isEnabled:PRMKeyLoopVideos] ? @"" : @", loop off"]
                 forKey:@"video state"];

    if (![PRMPrefs isEnabled:PRMKeyLoopVideos]) return;
    [PRMDebug noteAction:@"video playDidEnd"];

    // Held weakly so the reading never keeps the controller alive and never
    // reports a dead one. A restart driven by the host lands within a frame
    // or two, so this is late enough to catch it.
    __weak id pending = controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id later = pending;
        [PRMDebug setStatus:(later == nil) ? @"controller gone"
                          : [NSString stringWithFormat:@"perm/ready/playing %@",
                             PSGPlaybackFlags(later)]
                     forKey:@"video after"];
    });
}

%end
