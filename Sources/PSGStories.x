// Story playback and the reply bar.
// Signatures taken from the binary:
//   -[LSStoryBucketViewController startTimer]                   v16@0:8
//   -[LSStoryBucketViewController _addReplyBarViewController]   v16@0:8
//   -[LSStoryBucketViewController _configureReplyBar]           v16@0:8

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

- (void)startTimer {
    [PRMDebug noteHook:@"story timer"];
    %orig;
}


// Story videos start muted because this answers YES. Measured on 575:
// B16@0:8, 29 instructions, 8 calls -- it consults conditions before
// answering, and its verdict is replaced rather than its body read.
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

#pragma mark - Impression probe

// A second channel that might feed the seen list, measured on 575 at 18
// instructions and 10 calls. Nothing is swallowed: it is counted, so a
// second account can say whether the seen hook alone was enough.
%hook LSStoryViewerContentController

- (void)startImpressionTrackingWithAuthDataContext:(id)context
                             impressionTrackingParams:(id)params
                             storyBucketViewController:(id)controller {
    [PRMDebug noteHook:@"story impression"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"started with %@",
                         params ? NSStringFromClass([params class]) : @"nil"]
                 forKey:@"story impression"];
    %orig;
}

%end
