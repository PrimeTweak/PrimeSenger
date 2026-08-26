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
