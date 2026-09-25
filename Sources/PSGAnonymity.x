// Read receipts, story views, screenshot notices and the typing indicator,
// cut where the app publishes them rather than where it displays them.

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

// The message list's own screenshot handler, which sends the notice in an
// encrypted chat.
- (void)_handleUserDidTakeScreenshot:(id)note {
    [PRMDebug noteHook:@"screenshot chat"];
    if ([PRMPrefs isEnabled:PRMKeyBlockScreenshotNotice]) {
        [PRMDebug noteAction:@"screenshot chat"];
        [PRMDebug setStatus:@"chat notice swallowed" forKey:@"screenshot chat"];
        return;
    }
    %orig;
}

// Sets the host's own disableReadReceipts flag, which stops the receipt at
// the source rather than only silencing local observers.
- (void)viewDidLoad {
    %orig;

    // Reached through key-value coding rather than the ivar layout: inside
    // a hook the class is only forward declared, so self has no interface
    // and the runtime calls cannot be typed.
    id target = (id)self;
    BOOL wanted = ![PRMPrefs isEnabled:PRMKeyMasterDisable]
               && [PRMPrefs isEnabled:PRMKeyReadAnonymously];

    @try {
        NSNumber *before = [target valueForKey:@"disableReadReceipts"];
        [target setValue:@(wanted) forKey:@"disableReadReceipts"];
        [PSGReadReceipts setLiveController:wanted ? target : nil];
        [PRMDebug setStatus:[NSString stringWithFormat:@"disableReadReceipts %@ -> %@",
                             before.boolValue ? @"YES" : @"NO",
                             wanted ? @"YES" : @"NO"]
                     forKey:@"read receipts"];
    } @catch (NSException *problem) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"key unreachable: %@",
                             problem.name]
                     forKey:@"read receipts"];
    }
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

#pragma mark - What actually leaves the phone

// The emitters: the typing event, the mark-as-read flag every send carries,
// and the account settings encrypted chats consult.

static id PSGTypingArgument(id typing, NSString *side) {
    [PRMDebug noteHook:[@"typing publish " stringByAppendingString:side]];
    NSString *shape = typing == nil ? @"nil"
                    : [typing isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%@", typing]
                    : NSStringFromClass([typing class]);
    if (![PRMPrefs isEnabled:PRMKeyHideTypingIndicator]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"%@ passed %@", side, shape]
                     forKey:@"typing publish"];
        return typing;
    }
    [PRMDebug noteAction:[@"typing publish " stringByAppendingString:side]];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ forced NO (was %@)", side, shape]
                 forKey:@"typing publish"];
    return @NO;
}

%hook MCMTypingIndicatorPublishEventMutationBuilder

+ (id)builderWithIsTyping:(id)typing threadId:(id)threadId {
    id forced = PSGTypingArgument(typing, @"class");
    id result = %orig(forced, threadId);
    return result;
}

- (id)builderWithIsTyping:(id)typing threadId:(id)threadId {
    id forced = PSGTypingArgument(typing, @"instance");
    id result = %orig(forced, threadId);
    return result;
}

%end

// NO unless On reply is the chosen mode: Off and Manual both mean a reply
// must not mark the chat as read by itself.
static BOOL PSGMarkReadAllowed(BOOL requested) {
    if (![PRMPrefs isEnabled:PRMKeyReadAnonymously]) return requested;
    if ([PRMPrefs isEnabled:PRMKeyReadOnReply]) return requested;
    return NO;
}

%hook MSGSendMessageTextOptionalInputBuilder

- (id)withMarkRead:(BOOL)markRead {
    [PRMDebug noteHook:@"send mark read"];
    BOOL allowed = PSGMarkReadAllowed(markRead);
    if (allowed != markRead) [PRMDebug noteAction:@"send mark read"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"text %d -> %d", markRead, allowed]
                 forKey:@"send mark read"];
    id result = %orig(allowed);
    return result;
}

%end

%hook MSGSendMessageStickerOptionalInputBuilder

- (id)withMarkRead:(BOOL)markRead {
    [PRMDebug noteHook:@"send mark read"];
    BOOL allowed = PSGMarkReadAllowed(markRead);
    if (allowed != markRead) [PRMDebug noteAction:@"send mark read"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"sticker %d -> %d", markRead, allowed]
                 forKey:@"send mark read"];
    id result = %orig(allowed);
    return result;
}

%end

%hook MPESettings

- (BOOL)_isReadReceiptsDisabledFromPersistentStorage {
    BOOL original = %orig;
    [PRMDebug noteHook:@"mpe read receipts"];
    if (![PRMPrefs isEnabled:PRMKeyReadAnonymously]) return original;
    if (!original) [PRMDebug noteAction:@"mpe read receipts"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"stored %d -> disabled", original]
                 forKey:@"mpe read receipts"];
    return YES;
}

- (BOOL)_isTypingIndicatorsDisabledFromPersistentStorage {
    BOOL original = %orig;
    [PRMDebug noteHook:@"mpe typing"];
    if (![PRMPrefs isEnabled:PRMKeyHideTypingIndicator]) return original;
    if (!original) [PRMDebug noteAction:@"mpe typing"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"stored %d -> disabled", original]
                 forKey:@"mpe typing"];
    return YES;
}

%end
