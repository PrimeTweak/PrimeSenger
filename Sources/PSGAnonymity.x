// Read receipts, story seen markers, and the typing indicator.
// Signatures taken from the binary:
//   -[MSGMessageListViewController _notifyObserversDidSetAsRead:]  v20@0:8B16
//   -[MSGStoryBucketsDataManager markStoriesAsSeen:bucketID:isStoryPeekView:completion:]
//                                                                  v44@0:8@16@24B32@?36
//   -[MSGStoryBucketsDataManager markTabViewTimeAndClearBadgeCount] v16@0:8
//   -[MSGTypingIndicatorView shouldHideTypingIndicator:]            v20@0:8B16

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGReadReceipts.h"

%hook MSGMessageListViewController

- (void)_notifyObserversDidSetAsRead:(BOOL)read {
    [PRMDebug noteHook:@"read receipt"];
    if (read && [PRMPrefs isEnabled:PRMKeyReadAnonymously]) {
        // Manual mode opens the gate for one call, raised by the thread bar.
        if ([PSGReadReceipts consumeGate]) {
            %orig;
            return;
        }
        [PRMDebug noteAction:@"read receipt"];
        [PRMDebug log:@"read receipt suppressed"];
        return;
    }
    %orig;
}

%end

%hook MSGStoryBucketsDataManager

- (void)markStoriesAsSeen:(id)stories
                 bucketID:(id)bucketID
          isStoryPeekView:(BOOL)peek
               completion:(id)completion {
    [PRMDebug noteHook:@"story seen"];
    if ([PRMPrefs isEnabled:PRMKeyStoriesAnonymously]) {
        [PRMDebug noteAction:@"story seen"];
        [PRMDebug log:@"story seen suppressed for bucket %@", bucketID];
        return;
    }
    %orig;
}

- (void)markTabViewTimeAndClearBadgeCount {
    [PRMDebug noteHook:@"stories badge"];
    if ([PRMPrefs isEnabled:PRMKeyStoriesAnonymously]) {
        [PRMDebug noteAction:@"stories badge"];
        return;
    }
    %orig;
}

%end

%hook MSGTypingIndicatorView

// This is a setter, not a getter: void return, BOOL parameter. Forcing the
// argument to YES keeps the indicator hidden.
- (void)shouldHideTypingIndicator:(BOOL)hide {
    [PRMDebug noteHook:@"typing indicator"];
    if (!hide && [PRMPrefs isEnabled:PRMKeyHideTypingIndicator]) {
        [PRMDebug noteAction:@"typing indicator"];
        %orig(YES);
        return;
    }
    %orig;
}

%end
