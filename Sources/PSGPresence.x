// Active status.
//
// The first attempt swallowed the app-state report on the ObjC side, and a
// second account still saw the green dot. Measured since: the MQTT client in
// LightSpeedEngine tracks foreground itself in stripped C++
// ("connection/app_state {foreground %d -> %d}") and cannot be reached from
// here. Only the host's own setting reliably silences every channel.
//
// So the route is Messenger's own Active Status switch, turned off by the
// person, plus a lie about it where Meta enforces the trade-off: the client
// reports the setting to the server on two paths, and the server stops
// sending others' presence once it hears "off". If the server hears "on"
// while the client publishes nothing, others may keep arriving.
//
// Measured on 575, every path this touches or watches:
//
//   report to the server
//     -[MSGPresenceUtilsUserScopedPlugin MSGPresenceUtilsProvider_MSGReportUserPresenceSetting:]  v24@0:8@16
//     -[MSGPresenceUPCTransport reportPresenceSetting:coPresenceEnabled:]   v24@0:8B16B20
//     +[FBUpdatePerPlatformPresenceSettingsData dataWithActorId:isActive:platform:]  @36@0:8@16B24@28
//   the local reading of the setting, shared by publishers and displays
//     -[MSGPresenceUtilsUserScopedPlugin MSGPresenceUtilsProvider_MSGGlobalMessengerActiveStatusSettingIsEnabled:]  B24@0:8@16
//     -[MSGGlobalMessengerActiveStatusSettingObserver isEnabled]   B16@0:8
//     -[LSPresenceUserScopedPlugin _isEnabled]                      B16@0:8
//   what comes back from the server
//     -[MSGThreadPresenceObserver setCurrentStatusForThread:threadQueryKey:]  v32@0:8@16@24
//     -[MSGActiveNowListViewController updateActiveNowListWithModels:]        v24@0:8@16
//     -[MSGThreadViewPresenceFetchManager issueOnDemandPresenceFetch]        v16@0:8
//   the app-state reports, observed and no longer swallowed
//     -[MSGPresenceUtilsUserScopedPlugin MSGPresenceUtilsProvider_MSGReportAppState:]  v24@0:8@16
//     -[MSGPresenceUPCTransport reportAppState:]   v24@0:8q16
//
// With the switch off everything here only records. With it on, the three
// reports say "on", and the local reading answers YES to callers that are
// not publishing, decided from the call stack and recorded so the split can
// be checked. Whether the server then shows the person as active anyway is
// the one thing only a second account can answer.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>

#pragma mark - Recording

// The frames above a hook, reduced to method names. LightSpeedCore keeps its
// symbols, so the names are real.
static NSString *PSGCallers(void) {
    NSArray<NSString *> *frames = [NSThread callStackSymbols];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSRegularExpression *pattern =
        [NSRegularExpression regularExpressionWithPattern:@"[-+]\\[[^\\]]+\\]" options:0 error:NULL];
    for (NSUInteger i = 2; i < frames.count && names.count < 4; i++) {
        NSTextCheckingResult *match =
            [pattern firstMatchInString:frames[i] options:0 range:NSMakeRange(0, frames[i].length)];
        if (match == nil) continue;
        NSString *name = [frames[i] substringWithRange:match.range];
        if ([name containsString:@"_logos_"] || [name containsString:@"PSG"]) continue;
        [names addObject:name];
    }
    return names.count ? [names componentsJoinedByString:@" < "] : @"(no symbols)";
}

// Distinct caller chains per key, capped, so one reading lists who reads a
// value rather than how many times the busiest one did.
static void PSGRememberCallers(NSString *key, NSString *chain) {
    static NSMutableDictionary<NSString *, NSMutableOrderedSet<NSString *> *> *seen = nil;
    if (seen == nil) seen = [NSMutableDictionary dictionary];
    NSMutableOrderedSet<NSString *> *set = seen[key];
    if (set == nil) { set = [NSMutableOrderedSet orderedSet]; seen[key] = set; }
    if (set.count < 8) [set addObject:chain];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%lu chains | %@",
                         (unsigned long)set.count,
                         [set.array componentsJoinedByString:@" || "]]
                 forKey:[key stringByAppendingString:@" callers"]];
}

// A reader on the publishing side is left alone; anything else is a display
// and gets the lie. Decided from the chain, which is recorded either way.
static BOOL PSGChainPublishes(NSString *chain) {
    static NSArray<NSString *> *marks = nil;
    if (marks == nil) marks = @[@"Report", @"Publish", @"Transport", @"UPC", @"Mutation",
                                @"AppState", @"MQTT", @"Sync"];
    for (NSString *mark in marks) {
        if ([chain containsString:mark]) return YES;
    }
    return NO;
}

static BOOL PSGLie(void) {
    return [PRMPrefs isEnabled:PRMKeyAppearOffline];
}

// One shared decision for the three local readers.
static BOOL PSGLocalReading(BOOL original, NSString *key, NSString *extra) {
    [PRMDebug noteHook:key];
    NSString *chain = PSGCallers();
    PSGRememberCallers(key, chain);

    if (!PSGLie()) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"%d%@ | %@", original, extra ?: @"", chain]
                     forKey:key];
        return original;
    }
    BOOL publishes = PSGChainPublishes(chain);
    BOOL answer = publishes ? original : YES;
    if (answer != original) [PRMDebug noteAction:key];
    [PRMDebug setStatus:[NSString stringWithFormat:@"%d -> %d %@%@ | %@",
                         original, answer, publishes ? @"publisher" : @"display",
                         extra ?: @"", chain]
                 forKey:key];
    return answer;
}

#pragma mark - The plugin

%hook MSGPresenceUtilsUserScopedPlugin

- (BOOL)MSGPresenceUtilsProvider_MSGGlobalMessengerActiveStatusSettingIsEnabled:(id)argument {
    BOOL original = %orig;
    NSString *shape = argument == nil ? @""
                    : [NSString stringWithFormat:@" arg=%@", NSStringFromClass([argument class])];
    return PSGLocalReading(original, @"setting read", shape);
}

- (BOOL)MSGPresenceUtilsProvider_MSGGlobalMessengerActiveStatusSettingIsEligible {
    BOOL original = %orig;
    [PRMDebug setStatus:[NSString stringWithFormat:@"%d", original] forKey:@"setting eligible"];
    return original;
}

- (void)MSGPresenceUtilsProvider_MSGReportUserPresenceSetting:(id)setting {
    [PRMDebug noteHook:@"setting report"];
    NSString *shape = setting == nil ? @"nil"
                    : [setting isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%@", setting]
                    : NSStringFromClass([setting class]);
    PSGRememberCallers(@"setting report", PSGCallers());

    if (PSGLie() && [setting isKindOfClass:[NSNumber class]]) {
        [PRMDebug noteAction:@"setting report"];
        [PRMDebug setStatus:[NSString stringWithFormat:@"plugin %@ -> YES", shape]
                     forKey:@"setting report"];
        %orig(@YES);
        return;
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"plugin %@ passed", shape]
                 forKey:@"setting report"];
    %orig;
}

- (void)MSGPresenceUtilsProvider_MSGReportAppState:(id)state {
    [PRMDebug noteHook:@"presence report"];
    NSString *shape = state == nil ? @"nil"
                    : [state isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%@", state]
                    : NSStringFromClass([state class]);
    [PRMDebug setStatus:[NSString stringWithFormat:@"state %@ passed", shape]
                 forKey:@"presence report"];
    %orig;
}

- (BOOL)MSGPresenceUtilsProvider_MSGActiveStatusPauseExpireIfNeeded {
    BOOL original = %orig;
    [PRMDebug setStatus:[NSString stringWithFormat:@"expire %d", original] forKey:@"pause"];
    return original;
}

%end

#pragma mark - The transport

%hook MSGPresenceUPCTransport

- (void)reportPresenceSetting:(BOOL)enabled coPresenceEnabled:(BOOL)coPresence {
    [PRMDebug noteHook:@"setting report"];
    PSGRememberCallers(@"setting report", PSGCallers());
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
    [PRMDebug setStatus:[NSString stringWithFormat:@"state %lld passed", state]
                 forKey:@"presence transport"];
    %orig;
}

%end

#pragma mark - The GraphQL report

%hook FBUpdatePerPlatformPresenceSettingsData

+ (id)dataWithActorId:(id)actor isActive:(BOOL)active platform:(id)platform {
    [PRMDebug noteHook:@"setting report"];
    PSGRememberCallers(@"setting report", PSGCallers());
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

#pragma mark - The other local readers

%hook MSGGlobalMessengerActiveStatusSettingObserver

- (BOOL)isEnabled {
    BOOL original = %orig;
    return PSGLocalReading(original, @"observer read", nil);
}

%end

%hook LSPresenceUserScopedPlugin

- (BOOL)_isEnabled {
    BOOL original = %orig;
    return PSGLocalReading(original, @"ls presence read", nil);
}

%end

%hook MSGCoPresenceUserScopedPlugin

- (BOOL)MSGCoPresenceSettingProvider_MSGPresenceSettingsIsCoPresenceEnabled {
    BOOL original = %orig;
    [PRMDebug setStatus:[NSString stringWithFormat:@"%d", original] forKey:@"co-presence"];
    return original;
}

%end

#pragma mark - What arrives

// Nothing here is changed. Each one says whether the server keeps sending
// presence while the setting is off, which is the whole question.
%hook MSGThreadPresenceObserver

- (void)setCurrentStatusForThread:(id)status threadQueryKey:(id)key {
    %orig;
    [PRMDebug noteHook:@"presence arrives"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"thread status %@",
                         status ? [status description] : @"nil"]
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

%hook MSGThreadViewPresenceFetchManager

- (void)issueOnDemandPresenceFetch {
    [PRMDebug noteHook:@"presence fetch"];
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
