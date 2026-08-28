// Media permission gates. Messenger performs the save, share or forward
// itself once these return YES, so nothing here implements any of them.
//
// Every gate has the same shape, so the body lives in one helper rather than
// in a dozen copies. A refusal becomes an allowance; an allowance is left
// alone, so the switch can only ever open a door, never close one.
//
// Signatures taken from the host binary. All thirteen are present on both
// LSMediaViewController and LSMediaVideoViewController:
//   -[LSMediaViewController canSaveMedia]              B16@0:8
//   -[LSMediaViewController canShareMedia]             B16@0:8
//   -[LSMediaViewController canForwardMedia]           B16@0:8
//   -[LSMediaViewController canCopyMedia]              B16@0:8
//   -[LSMediaViewController canEditMedia]              B16@0:8
//   -[LSMediaViewController canReplyMedia]             B16@0:8
//   -[LSMediaViewController canGetInfo]                B16@0:8
//   -[LSMediaViewController canShowLiveText]           B16@0:8
//   -[LSMediaViewController canMediaAddToStory]        B16@0:8
//   -[LSMediaViewController canMediaAddToSharedAlbum]  B16@0:8
//   -[LSMediaViewController canOpenUnifiedShareSheet]  B16@0:8
//   -[LSMediaViewController isContentCensored]         B16@0:8
//   -[LSMediaViewController markViewOnceMessageAsOpened:]  v24@0:8@16

#import "PSGMedia.h"
#import "PRMPrefs.h"
#import "PRMDebug.h"

// Counted on every call, acted only when a refusal is reversed, so the two
// numbers read as questions asked against refusals overturned.
BOOL PSGUnlockGate(BOOL original, NSString *name) {
    [PRMDebug noteHook:name];
    if (original) return YES;
    if (![PRMPrefs isEnabled:PRMKeyUnlockMedia]) return NO;
    [PRMDebug noteAction:name];
    return YES;
}

// The censor flag runs the other way: YES means the media is covered.
BOOL PSGCensorGate(BOOL original, NSString *name) {
    [PRMDebug noteHook:name];
    if (!original) return NO;
    if (![PRMPrefs isEnabled:PRMKeyRevealCensored]) return YES;
    [PRMDebug noteAction:name];
    return NO;
}

%hook LSMediaViewController

- (BOOL)canSaveMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canSaveMedia");
}

- (BOOL)canShareMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canShareMedia");
}

- (BOOL)canForwardMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canForwardMedia");
}

- (BOOL)canCopyMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canCopyMedia");
}

- (BOOL)canEditMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canEditMedia");
}

- (BOOL)canReplyMedia {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canReplyMedia");
}

- (BOOL)canGetInfo {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canGetInfo");
}

- (BOOL)canShowLiveText {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canLiveText");
}

- (BOOL)canMediaAddToStory {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canAddToStory");
}

- (BOOL)canMediaAddToSharedAlbum {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canAddToAlbum");
}

- (BOOL)canOpenUnifiedShareSheet {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canShareSheet");
}

- (BOOL)isContentCensored {
    BOOL original = %orig;
    return PSGCensorGate(original, @"censored");
}

// A View once photo or video burns when the host marks it as opened, and
// this is the method that marks it. Swallowing the call leaves the media
// unmarked, so it stays openable.
//
// The original is called on every other path, so the media behaves normally
// while the switch is off.
- (void)markViewOnceMessageAsOpened:(id)message {
    [PRMDebug noteHook:@"view once"];
    if (![PRMPrefs isEnabled:PRMKeyViewOnce]) {
        %orig;
        return;
    }
    [PRMDebug noteAction:@"view once"];
}

%end
