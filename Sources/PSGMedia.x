// Media permission gates. Messenger performs the save itself once these
// return YES, so nothing here implements downloading.
// Signatures taken from the binary:
//   -[LSMediaViewController canSaveMedia]     B16@0:8
//   -[LSMediaViewController canShareMedia]    B16@0:8
//   -[LSMediaViewController canForwardMedia]  B16@0:8

#import "PRMPrefs.h"
#import "PRMDebug.h"

%hook LSMediaViewController

- (BOOL)canSaveMedia {
    [PRMDebug noteHook:@"canSaveMedia"];
    BOOL original = %orig;
    if (!original && [PRMPrefs isEnabled:PRMKeyUnlockMedia]) {
        [PRMDebug noteAction:@"canSaveMedia"];
        return YES;
    }
    return original;
}

- (BOOL)canShareMedia {
    [PRMDebug noteHook:@"canShareMedia"];
    BOOL original = %orig;
    if (!original && [PRMPrefs isEnabled:PRMKeyUnlockMedia]) {
        [PRMDebug noteAction:@"canShareMedia"];
        return YES;
    }
    return original;
}

- (BOOL)canForwardMedia {
    [PRMDebug noteHook:@"canForwardMedia"];
    BOOL original = %orig;
    if (!original && [PRMPrefs isEnabled:PRMKeyUnlockMedia]) {
        [PRMDebug noteAction:@"canForwardMedia"];
        return YES;
    }
    return original;
}

%end
