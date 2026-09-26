// Suggested people in the Notifications tab, emptied on every read so
// nothing is kept that could bring them back.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import "PSGSilence.h"

%hook MSGJewelNotificationDataManager

- (id)peopleYouMayKnowSuggestionJewels {
    [PRMDebug noteHook:@"notif pymk jewels"];
    id original = %orig;
    if (![PRMPrefs isEnabled:PRMKeyHidePymkInNotifications]) return original;

    [PRMDebug noteAction:@"notif pymk jewels"];
    [PRMDebug log:@"emptied %lu notification suggestions",
                  (unsigned long)[original count]];
    return @[];
}

- (unsigned long long)peopleYouMayKnowSuggestionJewelsCount {
    [PRMDebug noteHook:@"notif pymk count"];
    if ([PRMPrefs isEnabled:PRMKeyHidePymkInNotifications]) {
        [PRMDebug noteAction:@"notif pymk count"];
        return 0;
    }
    return %orig;
}

- (id)_convertPeopleYouMayKnowSuggestionsToJewels {
    [PRMDebug noteHook:@"notif pymk convert"];
    if ([PRMPrefs isEnabled:PRMKeyHidePymkInNotifications]) {
        [PRMDebug noteAction:@"notif pymk convert"];
        return @[];
    }
    return %orig;
}

%end

#pragma mark - Silenced chats

// Where the app decides whether a notification is shown. A chat muted with
// the bell gets no presentation; anything unexpected passes through.
%hook MSGThreadListViewController

- (id)notificationPresentationOptionsWithThreadKey:(id)threadKey
                                        recipientID:(id)recipientID
                                 pushLogMessageType:(int)logType
                                    pushPayloadType:(int)payloadType {
    id original = %orig;
    [PRMDebug noteHook:@"silence"];

    NSString *identifier = [PSGSilence identifierForThreadKey:threadKey];
    NSString *shape = original == nil ? @"nil"
                    : [original isKindOfClass:[NSNumber class]]
                        ? [NSString stringWithFormat:@"NSNumber %@", original]
                        : NSStringFromClass([original class]);
    NSString *keyShape = threadKey ? NSStringFromClass([threadKey class]) : @"nil";

    BOOL wanted = [PRMPrefs isEnabled:PRMKeySilencedChats] && [PSGSilence isSilenced:identifier];
    BOOL applied = wanted && [original isKindOfClass:[NSNumber class]];

    [PRMDebug setStatus:[NSString stringWithFormat:
                         @"key %@ (%@) | returns %@ | types %d/%d | %@",
                         identifier ?: @"-", keyShape, shape, logType, payloadType,
                         applied ? @"SILENCED" : (wanted ? @"wanted, shape unknown" : @"passed")]
                 forKey:@"silence"];

    if (applied) {
        [PRMDebug noteAction:@"silence"];
        return @0;
    }
    return original;
}

%end
