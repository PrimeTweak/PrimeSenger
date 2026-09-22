// Active status.
//
// Measured across three builds and two accounts:
//
//   The server enforces the trade-off. With the native switch off it reported
//   "off" and nothing came back (presence arrives: never). Reporting "on"
//   instead brought others back (presence arrives: 3) -- and the server
//   synced "on" to the phone, which flipped the local cache to 1, restarted
//   the ObjC publishers (presence report: 1 -> 3) and pinned the native
//   switch on.
//
//   The transport is the bridge to the C++ presence manager: its ivar
//   _presenceManager is a shared_ptr<facebook::presence::UnifiedPresenceManager>,
//   so reportAppState: on the transport is where foreground reaches it.
//
//   The local cache lives in LSPresenceUserScopedPlugin._cachedPresenceEnabled
//   (NSNumber), refreshed by _handleActiveStatusChangeNotification:, read by
//   _isEnabled some 150 times a session. It is what the ObjC publishers
//   consult.
//
// So the stable state to aim for is: server told "on", phone kept "off".
// With the switch on, this build does all of it at once, each part recorded:
//
//   1. the three reports to the server say "on"
//   2. the sync landing is watched and the local cache pinned to NO right
//      after it, so the plugin never learns the server flipped it
//   3. _isEnabled answers NO, so the ObjC publishers stay quiet
//   4. both app-state reports are swallowed as well, so nothing reaches the
//      presence manager even if a publisher slips through
//
// The one question left is whether others' presence still displays while
// _isEnabled answers NO, since presence arrives regardless. That is read
// from the screen, and if the dots are gone the display gate is _isEnabled
// and needs its own split.
//
// The native pause is watched too: if pausing keeps the server on while the
// phone stops publishing, Meta already ships the mechanism and a pause that
// never expires is the whole feature.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL PSGLie(void) {
    return [PRMPrefs isEnabled:PRMKeyAppearOffline];
}

static NSString *PSGShape(id value) {
    if (value == nil) return @"nil";
    if ([value isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"%@", value];
    return NSStringFromClass([value class]);
}

#pragma mark - The local cache

%hook LSPresenceUserScopedPlugin

// Where the server's value lands. Recorded, passed through, and the cache
// pinned back to NO right after so the phone keeps "off".
- (void)_handleActiveStatusChangeNotification:(id)note {
    %orig;
    [PRMDebug noteHook:@"presence sync"];

    id plugin = self;
    Ivar slot = class_getInstanceVariable(object_getClass(plugin), "_cachedPresenceEnabled");
    id cached = slot ? object_getIvar(plugin, slot) : nil;
    NSString *before = PSGShape(cached);

    if (PSGLie() && slot != NULL) {
        object_setIvar(plugin, slot, @NO);
        [PRMDebug noteAction:@"presence sync"];
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"note %@ | cache %@%@",
                         PSGShape(note), before, PSGLie() ? @" -> 0 pinned" : @""]
                 forKey:@"presence sync"];
}

- (BOOL)_isEnabled {
    BOOL original = %orig;
    [PRMDebug noteHook:@"ls presence read"];

    id plugin = self;
    Ivar slot = class_getInstanceVariable(object_getClass(plugin), "_cachedPresenceEnabled");
    Ivar cachingSlot = class_getInstanceVariable(object_getClass(plugin), "_isCachingEnabled");
    id cached = slot ? object_getIvar(plugin, slot) : nil;
    BOOL caching = NO;
    if (cachingSlot != NULL) {
        caching = ((const char *)(__bridge const void *)plugin)[ivar_getOffset(cachingSlot)] != 0;
    }

    if (!PSGLie()) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"%d | cache %@ caching %d",
                             original, PSGShape(cached), caching]
                     forKey:@"ls presence read"];
        return original;
    }
    if (original) [PRMDebug noteAction:@"ls presence read"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%d -> 0 | cache %@ caching %d",
                         original, PSGShape(cached), caching]
                 forKey:@"ls presence read"];
    return NO;
}

%end

#pragma mark - The plugin

%hook MSGPresenceUtilsUserScopedPlugin

- (void)MSGPresenceUtilsProvider_MSGReportUserPresenceSetting:(id)setting {
    [PRMDebug noteHook:@"setting report"];
    if (PSGLie() && [setting isKindOfClass:[NSNumber class]]) {
        [PRMDebug noteAction:@"setting report"];
        [PRMDebug setStatus:[NSString stringWithFormat:@"plugin %@ -> YES", PSGShape(setting)]
                     forKey:@"setting report"];
        %orig(@YES);
        return;
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"plugin %@ passed", PSGShape(setting)]
                 forKey:@"setting report"];
    %orig;
}

- (void)MSGPresenceUtilsProvider_MSGReportAppState:(id)state {
    [PRMDebug noteHook:@"presence report"];
    if (PSGLie()) {
        [PRMDebug noteAction:@"presence report"];
        [PRMDebug setStatus:[NSString stringWithFormat:@"state %@ SWALLOWED", PSGShape(state)]
                     forKey:@"presence report"];
        return;
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"state %@ passed", PSGShape(state)]
                 forKey:@"presence report"];
    %orig;
}

- (BOOL)MSGPresenceUtilsProvider_MSGGlobalMessengerActiveStatusSettingIsEnabled:(id)argument {
    BOOL original = %orig;
    [PRMDebug noteHook:@"setting read"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%d arg %@", original, PSGShape(argument)]
                 forKey:@"setting read"];
    return original;
}

// The pause, watched. Expiry is a timestamp; a pause in force reads as a
// future one. With the switch on it is told never to expire, so a native
// pause the person starts becomes permanent.
- (BOOL)MSGPresenceUtilsProvider_MSGActiveStatusPauseExpireIfNeeded {
    BOOL original = %orig;
    [PRMDebug noteHook:@"pause"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"expire %d%@", original,
                         PSGLie() ? @" -> 0 held" : @""]
                 forKey:@"pause"];
    return PSGLie() ? NO : original;
}

- (id)MSGPresenceUtilsProvider_MSGActiveStatusPauseGetExpiry {
    id expiry = %orig;
    [PRMDebug setStatus:[NSString stringWithFormat:@"expiry %@", PSGShape(expiry)]
                 forKey:@"pause expiry"];
    return expiry;
}

- (BOOL)MSGPresenceUtilsProvider_MSGActiveStatusPauseStoreExpiry:(double)expiry {
    BOOL original = %orig;
    [PRMDebug noteHook:@"pause store"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"stored %.0f -> %d", expiry, original]
                 forKey:@"pause store"];
    return original;
}

%end

#pragma mark - The transport

%hook MSGPresenceUPCTransport

- (void)reportPresenceSetting:(BOOL)enabled coPresenceEnabled:(BOOL)coPresence {
    [PRMDebug noteHook:@"setting report"];
    if (PSGLie()) {
        [PRMDebug noteAction:@"setting report"];
        [PRMDebug setStatus:[NSString stringWithFormat:@"transport %d/%d -> YES/%d",
                             enabled, coPresence, coPresence]
                     forKey:@"setting report"];
        %orig(YES, coPresence);
        return;
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"transport %d/%d passed", enabled, coPresence]
                 forKey:@"setting report"];
    %orig;
}

- (void)reportAppState:(long long)state {
    [PRMDebug noteHook:@"presence transport"];
    if (PSGLie()) {
        [PRMDebug noteAction:@"presence transport"];
        [PRMDebug setStatus:[NSString stringWithFormat:@"state %lld SWALLOWED", state]
                     forKey:@"presence transport"];
        return;
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"state %lld passed", state]
                 forKey:@"presence transport"];
    %orig;
}

%end

#pragma mark - The GraphQL report

%hook FBUpdatePerPlatformPresenceSettingsData

+ (id)dataWithActorId:(id)actor isActive:(BOOL)active platform:(id)platform {
    [PRMDebug noteHook:@"setting report"];
    if (PSGLie()) {
        [PRMDebug noteAction:@"setting report"];
        [PRMDebug setStatus:[NSString stringWithFormat:@"graphql %d -> YES on %@", active, platform]
                     forKey:@"setting report"];
        id result = %orig(actor, YES, platform);
        return result;
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"graphql %d passed on %@", active, platform]
                 forKey:@"setting report"];
    id result = %orig;
    return result;
}

%end

#pragma mark - What arrives

%hook MSGThreadPresenceObserver

- (void)setCurrentStatusForThread:(id)status threadQueryKey:(id)key {
    %orig;
    [PRMDebug noteHook:@"presence arrives"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"thread status %@", PSGShape(status)]
                 forKey:@"presence arrives"];
}

%end

%hook MSGActiveNowListViewController

- (void)updateActiveNowListWithModels:(id)models {
    %orig;
    [PRMDebug noteHook:@"active now list"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%lu models",
                         (unsigned long)([models isKindOfClass:[NSArray class]]
                                         ? [(NSArray *)models count] : 0)]
                 forKey:@"active now list"];
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
