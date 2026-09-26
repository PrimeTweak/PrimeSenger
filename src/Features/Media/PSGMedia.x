// Media permission gates. Messenger performs each action itself once its
// gate answers YES; a refusal becomes an allowance, never the reverse.

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

// View in chat, from the media viewer.
- (BOOL)canViewMediaInThread {
    BOOL original = %orig;
    return PSGUnlockGate(original, @"canViewInThread");
}

// A View once photo burns when the host marks it opened. Skipping that
// call keeps it openable; with the switch off it runs as usual.
- (void)markViewOnceMessageAsOpened:(id)message {
    [PRMDebug noteHook:@"view once"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"called, arg=%@",
                         message ? NSStringFromClass([message class]) : @"nil"]
                 forKey:@"view once"];

    if (![PRMPrefs isEnabled:PRMKeyViewOnce]) {
        %orig;
        return;
    }
    [PRMDebug noteAction:@"view once"];
}

%end

#pragma mark - Meta AI in the media menu

// Ask Meta AI in the media menu, closed like the censorship gate.
%hook LSThreadMediaViewerBucketViewController

- (BOOL)canOpenMetaAIChat {
    BOOL original = %orig;
    [PRMDebug noteHook:@"meta ai media"];
    if (![PRMPrefs isEnabled:PRMKeyHideMetaAIMedia]) return original;
    if (original) [PRMDebug noteAction:@"meta ai media"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"host %@ -> hidden", original ? @"offered" : @"absent"]
                 forKey:@"meta ai media"];
    return NO;
}

%end
