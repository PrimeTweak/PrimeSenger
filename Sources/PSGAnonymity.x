// Read receipts, story seen markers, and the typing indicator.
// Signatures taken from the binary:
//   -[MSGMessageListViewController _notifyObserversDidSetAsRead:]  v20@0:8B16
//   -[MSGStoryBucketsDataManager markStoriesAsSeen:bucketID:isStoryPeekView:completion:]
//                                                                  v44@0:8@16@24B32@?36
//   -[MSGStoryBucketsDataManager markTabViewTimeAndClearBadgeCount] v16@0:8

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

// The host carries its own flag for this, passed to the initialiser as
// disableReadReceipts: and kept in the _disableReadReceipts ivar. Setting it
// stops the receipt at the source; suppressing -_notifyObserversDidSetAsRead:
// only silences local observers, so the receipt still reached the server.
// Measured on 575: the message list handles a screenshot itself, 64
// instructions and 32 calls, which is the notice sent in an encrypted chat.
// The ephemeral viewer hook in PSGStoryCapture.x never saw this path.
- (void)_handleUserDidTakeScreenshot:(id)note {
    [PRMDebug noteHook:@"screenshot chat"];
    if ([PRMPrefs isEnabled:PRMKeyBlockScreenshotNotice]) {
        [PRMDebug noteAction:@"screenshot chat"];
        [PRMDebug setStatus:@"chat notice swallowed" forKey:@"screenshot chat"];
        return;
    }
    %orig;
}

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

// The hooks above act on what the message list shows. These act on what the
// app publishes, measured on 575 as the real emitters:
//
//   +[MCMTypingIndicatorPublishEventMutationBuilder builderWithIsTyping:threadId:]
//       @32@0:8@16@24   the typing event itself
//   -[MSGSendMessageTextOptionalInputBuilder withMarkRead:]      @20@0:8B16
//   -[MSGSendMessageStickerOptionalInputBuilder withMarkRead:]   @20@0:8B16
//       a send carries its own mark-as-read flag
//   -[MPESettings _isTypingIndicatorsDisabledFromPersistentStorage]   B16@0:8
//   -[MPESettings _isReadReceiptsDisabledFromPersistentStorage]       B16@0:8
//       the account settings encrypted chats consult
//
// The builder is hooked as both a class and an instance method: whichever
// one the host implements is the live one, the other is inert, and the
// counters say which fired.

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
