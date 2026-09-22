// Active status probe.
//
// Six passes closed the ObjC report paths, the local cache and the display
// gate. Three routes were never tested and are measured here at once, plus
// every presence surface, so one reading settles all of them.
//
// Route A, per-platform presence. Meta tracks the setting per platform
// (FBIOS, DESKTOP, FACEBOOK_WEB). The query and mutation are GraphQL data
// models with no instance methods to hook, so the effect is read from what
// arrives: if presence keeps coming while this device reports inactive,
// another platform is keeping the feed open.
//
// Route B, on-demand fetch. Measured present:
//   -[MSGPresenceUtilsUserScopedPlugin
//       MSGPresenceUtilsProvider_MSGOnDemandFetchContactsPresence:]  v24@0:8@16
//   -[MSGThreadViewPresenceFetchManager issueOnDemandPresenceFetch]  v16@0:8
// The switch fires an explicit fetch on every thread open; the reading says
// whether the server answers one while the native toggle is off.
//
// Route C, background state. Measured:
//   -[FBBackgroundStateProvider isAppBackgrounded]  B16@0:8
//   -[FBBackgroundStateProvider _didEnterBackground] / _willEnterForeground
// Forcing backgrounded to YES was assumed to cut messaging; never verified.
// Here it is only reported, with a received-message counter alongside, so
// the cost is measured before anything is forced.
//
// Nothing is swallowed and nothing is forced. Every hook records. The switch
// only arms the on-demand fetch on thread open, which is safe to observe.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

static NSString *PSGShape(id value) {
    if (value == nil) return @"nil";
    if ([value isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"%@", value];
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSArray class]])
        return [NSString stringWithFormat:@"[%lu]", (unsigned long)[(NSArray *)value count]];
    return NSStringFromClass([value class]);
}

#pragma mark - What arrives (the answer to every route)

%hook MSGThreadPresenceObserver

- (void)setCurrentStatusForThread:(id)status threadQueryKey:(id)key {
    %orig;
    [PRMDebug noteHook:@"presence arrives"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"status %@", PSGShape(status)]
                 forKey:@"presence arrives"];
}

%end

%hook MSGActiveNowListViewController

- (void)updateActiveNowListWithModels:(id)models {
    %orig;
    [PRMDebug noteHook:@"active now list"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ models", PSGShape(models)]
                 forKey:@"active now list"];
}

%end

#pragma mark - Route B, on-demand fetch

%hook MSGPresenceUtilsUserScopedPlugin

- (void)MSGPresenceUtilsProvider_MSGOnDemandFetchContactsPresence:(id)arg {
    [PRMDebug noteHook:@"ondemand fetch"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"called with %@", PSGShape(arg)]
                 forKey:@"ondemand fetch"];
    %orig;
}

// Still recorded, no longer swallowed, so the report path stays visible.
- (void)MSGPresenceUtilsProvider_MSGReportAppState:(id)state {
    [PRMDebug noteHook:@"presence report"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"state %@ passed", PSGShape(state)]
                 forKey:@"presence report"];
    %orig;
}

- (BOOL)MSGPresenceUtilsProvider_MSGGlobalMessengerActiveStatusSettingIsEnabled:(id)arg {
    BOOL original = %orig;
    [PRMDebug noteHook:@"setting read"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%d", original] forKey:@"setting read"];
    return original;
}

%end

%hook MSGThreadViewPresenceFetchManager

- (void)issueOnDemandPresenceFetch {
    [PRMDebug noteHook:@"fetch issued"];
    %orig;
}

%end

// The switch arms an explicit fetch each time a thread opens, so the reading
// shows whether the server answers one while the native toggle is off.
%hook MSGThreadViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![PRMPrefs isEnabled:PRMKeyAppearOffline]) return;

    id controller = self;
    id manager = nil;
    Ivar slot = class_getInstanceVariable(object_getClass(controller), "_presenceFetchManager");
    if (slot != NULL) manager = object_getIvar(controller, slot);

    if ([manager respondsToSelector:@selector(issueOnDemandPresenceFetch)]) {
        [PRMDebug noteAction:@"ondemand fetch"];
        [PRMDebug setStatus:@"forced on thread open" forKey:@"ondemand fetch"];
        ((void (*)(id, SEL))objc_msgSend)(manager, @selector(issueOnDemandPresenceFetch));
    } else {
        [PRMDebug setStatus:@"no fetch manager ivar" forKey:@"ondemand fetch"];
    }
}

%end

#pragma mark - Route C, background state

%hook FBBackgroundStateProvider

// Only read. The received-message counter below says whether messaging would
// survive if this were later forced.
- (BOOL)isAppBackgrounded {
    BOOL original = %orig;
    [PRMDebug noteHook:@"background state"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%d", original]
                 forKey:@"background state"];
    return original;
}

%end

#pragma mark - The messaging cost meter

// Every inbound message increments this. Read it across a session with the
// switch on: if it keeps climbing, the real-time channel is alive.
// Every message row generated, inbound included, so a climbing count over a
// session with the switch on means the real-time channel is alive.
%hook MSGMessageListViewController

- (void)messageRowDidGenerate:(id)row
               deliveryStatus:(long long)status
          isUpdatedMessageRow:(BOOL)updated {
    if (!updated) [PRMDebug noteHook:@"message row"];
    %orig;
}

%end

#pragma mark - The native switch

%hook MSGActiveStatusViewController

- (void)handleActiveStatusToggle:(BOOL)on {
    [PRMDebug noteHook:@"native toggle"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"native switch -> %d", on]
                 forKey:@"native toggle"];
    %orig;
}

%end
