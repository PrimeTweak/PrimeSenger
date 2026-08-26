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

%end
