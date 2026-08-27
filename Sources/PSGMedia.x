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

- (BOOL)canSaveMedia             { return PSGUnlockGate(%orig, @"canSaveMedia"); }
- (BOOL)canShareMedia            { return PSGUnlockGate(%orig, @"canShareMedia"); }
- (BOOL)canForwardMedia          { return PSGUnlockGate(%orig, @"canForwardMedia"); }
- (BOOL)canCopyMedia             { return PSGUnlockGate(%orig, @"canCopyMedia"); }
- (BOOL)canEditMedia             { return PSGUnlockGate(%orig, @"canEditMedia"); }
- (BOOL)canReplyMedia            { return PSGUnlockGate(%orig, @"canReplyMedia"); }
- (BOOL)canGetInfo               { return PSGUnlockGate(%orig, @"canGetInfo"); }
- (BOOL)canShowLiveText          { return PSGUnlockGate(%orig, @"canLiveText"); }
- (BOOL)canMediaAddToStory       { return PSGUnlockGate(%orig, @"canAddToStory"); }
- (BOOL)canMediaAddToSharedAlbum { return PSGUnlockGate(%orig, @"canAddToAlbum"); }
- (BOOL)canOpenUnifiedShareSheet { return PSGUnlockGate(%orig, @"canShareSheet"); }

- (BOOL)isContentCensored        { return PSGCensorGate(%orig, @"censored"); }

%end
