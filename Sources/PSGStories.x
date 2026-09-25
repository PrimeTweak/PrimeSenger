// Stories: the reply bar, and sound on video stories.

#import "PRMPrefs.h"
#import "PRMDebug.h"

%hook LSStoryBucketViewController

- (void)_addReplyBarViewController {
    [PRMDebug noteHook:@"story reply bar"];
    if ([PRMPrefs isEnabled:PRMKeyHideStoryReplyBar]) {
        [PRMDebug noteAction:@"story reply bar"];
        return;
    }
    %orig;
}

- (void)_configureReplyBar {
    [PRMDebug noteHook:@"configure reply bar"];
    if ([PRMPrefs isEnabled:PRMKeyHideStoryReplyBar]) {
        [PRMDebug noteAction:@"configure reply bar"];
        return;
    }
    %orig;
}

// Story videos start muted because this answers YES; its verdict is
// replaced when the switch is on.
- (BOOL)shouldDefaultVideoToMute {
    BOOL original = %orig;
    [PRMDebug noteHook:@"story sound"];
    if (![PRMPrefs isEnabled:PRMKeyStorySound]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"off, host says %@", original ? @"muted" : @"sound"]
                     forKey:@"story sound"];
        return original;
    }
    if (original) [PRMDebug noteAction:@"story sound"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"host %@ -> sound", original ? @"muted" : @"sound"]
                 forKey:@"story sound"];
    return NO;
}

%end
