// How a video plays, as opposed to what can be done with it.
//
// Measured on Messenger 575:
//
//   -[LSThreadMediaViewerContentController isAudioMuted]  B16@0:8   2 instructions, 0 calls
//   -[LSVideoPlayerView setRate:callsite:]                v28@0:8f16@20   4 instructions
//
// The first is a bare ivar read: the fullscreen viewer starts muted because
// this answers YES. The second is where every playback rate is set; the host
// passes 1.0 when it starts a video, and that is the value replaced.

#import "PRMPrefs.h"
#import "PRMDebug.h"

// The pill on the Speed row raises exactly one of the two keys.
static float PSGChosenRate(void) {
    if ([PRMPrefs isEnabled:PRMKeySpeed2]) return 2.0f;
    if ([PRMPrefs isEnabled:PRMKeySpeed15]) return 1.5f;
    return 1.0f;
}

%hook LSThreadMediaViewerContentController

- (BOOL)isAudioMuted {
    BOOL original = %orig;
    [PRMDebug noteHook:@"sound on open"];
    if (![PRMPrefs isEnabled:PRMKeySoundOnOpen]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"off, host says %@", original ? @"muted" : @"sound"]
                     forKey:@"sound on open"];
        return original;
    }
    if (original) [PRMDebug noteAction:@"sound on open"];
    [PRMDebug setStatus:[NSString stringWithFormat:@"host %@ -> sound", original ? @"muted" : @"sound"]
                 forKey:@"sound on open"];
    return NO;
}

%end

%hook LSVideoPlayerView

- (void)setRate:(float)rate callsite:(id)callsite {
    [PRMDebug noteHook:@"speed"];

    // Every rate the host sets is recorded with its callsite, so a reading
    // shows whether a seek or a restart puts it back to 1.0 after ours.
    static NSMutableArray<NSString *> *trace = nil;
    if (trace == nil) trace = [NSMutableArray array];
    NSString *site = [callsite isKindOfClass:[NSString class]] ? callsite
                   : (callsite ? NSStringFromClass([callsite class]) : @"-");
    [trace addObject:[NSString stringWithFormat:@"%.2g@%@", rate, site]];
    while (trace.count > 8) [trace removeObjectAtIndex:0];

    float chosen = PSGChosenRate();
    BOOL replace = [PRMPrefs isEnabled:PRMKeySpeed] && chosen != 1.0f && rate == 1.0f;
    [PRMDebug setStatus:[NSString stringWithFormat:@"%@ | %@",
                         replace ? [NSString stringWithFormat:@"1.0 -> %.1f", chosen] : @"passed",
                         [trace componentsJoinedByString:@" "]]
                 forKey:@"speed"];

    if (replace) {
        [PRMDebug noteAction:@"speed"];
        %orig(chosen, callsite);
        return;
    }
    %orig;
}

%end
