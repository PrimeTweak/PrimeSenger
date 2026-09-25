// Videos have their own controller with its own copy of every media gate,
// so the media switch covers both; the gate bodies are shared.

#import "PSGMedia.h"
#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <objc/message.h>
#import <objc/runtime.h>

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

// Loops through the host's own loop switch, armed once when a video
// appears, so Messenger replays it itself.
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

// Counts each end of playback while looping is on.
- (void)playDidEnd {
    [PRMDebug noteHook:@"video playDidEnd"];
    %orig;
    if ([PRMPrefs isEnabled:PRMKeyLoopVideos]) [PRMDebug noteAction:@"video playDidEnd"];
}

%end
