// Active status.
//
// Measured on Messenger 575: the app reports its own state to the presence
// system through one provider method, and that report is what makes the
// green dot appear for others.
//
//   -[MSGPresenceUtilsUserScopedPlugin MSGPresenceUtilsProvider_MSGReportAppState:]
//       v24@0:8@16, 64 instructions, 41 calls
//
// Swallowing it keeps the report from ever leaving the phone while the
// native setting stays on, so others' status is still shown. What is not
// measured is whether any other channel carries presence too; the effect can
// only be confirmed from a second account, which is why every call is
// recorded here whether the switch is on or off.

#import "PRMPrefs.h"
#import "PRMDebug.h"

%hook MSGPresenceUtilsUserScopedPlugin

- (void)MSGPresenceUtilsProvider_MSGReportAppState:(id)state {
    [PRMDebug noteHook:@"presence report"];

    // The value the host hands over, so a reading says which states pass
    // through here and how often.
    static NSMutableArray<NSString *> *trace = nil;
    if (trace == nil) trace = [NSMutableArray array];
    NSString *shape = state == nil ? @"nil"
                    : [state isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%@", state]
                    : NSStringFromClass([state class]);
    [trace addObject:shape];
    while (trace.count > 10) [trace removeObjectAtIndex:0];

    BOOL swallow = [PRMPrefs isEnabled:PRMKeyAppearOffline];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ | %@",
                         swallow ? @"SWALLOWED" : @"passed",
                         [trace componentsJoinedByString:@" "]]
                 forKey:@"presence report"];

    if (swallow) {
        [PRMDebug noteAction:@"presence report"];
        return;
    }
    %orig;
}

%end
