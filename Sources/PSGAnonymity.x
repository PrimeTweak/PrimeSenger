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
#import <objc/runtime.h>

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

// The host carries its own flag for this, passed to the initialiser as
// disableReadReceipts: and kept in the _disableReadReceipts ivar. Setting it
// stops the receipt at the source; suppressing -_notifyObserversDidSetAsRead:
// only silences local observers, so the receipt still reached the server.
- (void)viewDidLoad {
    %orig;

    Ivar flag = class_getInstanceVariable([self class], "_disableReadReceipts");
    if (flag == NULL) {
        [PRMDebug setStatus:@"_disableReadReceipts ivar NOT FOUND" forKey:@"read receipts"];
        return;
    }

    BOOL wanted = ![PRMPrefs isEnabled:PRMKeyMasterDisable]
               && [PRMPrefs isEnabled:PRMKeyReadAnonymously];

    ptrdiff_t offset = ivar_getOffset(flag);
    BOOL *slot = (BOOL *)((__bridge void *)self + offset);
    BOOL before = *slot;
    *slot = wanted;

    [PSGReadReceipts setLiveController:wanted ? self : nil];
    [PRMDebug setStatus:[NSString stringWithFormat:@"_disableReadReceipts %@ -> %@",
                         before ? @"YES" : @"NO", wanted ? @"YES" : @"NO"]
                 forKey:@"read receipts"];
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
