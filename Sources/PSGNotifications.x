// People You May Know inside the Notifications tab.
//
// The jewels are emptied on every read, so nothing is stored that could
// expire and bring the suggestions back.
//
// Signatures taken from the binary:
//   -[MSGJewelNotificationDataManager peopleYouMayKnowSuggestionJewels]       @16@0:8
//   -[MSGJewelNotificationDataManager peopleYouMayKnowSuggestionJewelsCount]  Q16@0:8
//   -[MSGJewelNotificationDataManager _convertPeopleYouMayKnowSuggestionsToJewels] @16@0:8

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

// The one point where the app decides whether an incoming notification is
// presented. Measured on 575:
//
//   -[MSGThreadListViewController notificationPresentationOptionsWithThreadKey:
//        recipientID:pushLogMessageType:pushPayloadType:]   @40@0:8@16@24i32i36
//       48 instructions, 19 calls
//
// The thread key arrives as the first argument. What the method returns is
// not measured yet: it may be a number wrapping the system presentation
// options, or a Meta object. Both cases are recorded, and the silence is only
// applied when the return is a number, where zero means no presentation.
// Any other shape passes through untouched and is named in the report.
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
