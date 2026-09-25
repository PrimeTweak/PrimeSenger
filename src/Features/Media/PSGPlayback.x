// How a video plays: sound when opened full screen, and a faster rate
// replacing the 1.0 the host sets when a video starts.

#import "PRMPrefs.h"
#import "PRMDebug.h"

// The pill switches between the two speeds.
static float PSGChosenRate(void) {
    return [PRMPrefs isEnabled:PRMKeySpeed2] ? 2.0f : 1.5f;
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

    float chosen = PSGChosenRate();
    BOOL replace = [PRMPrefs isEnabled:PRMKeySpeed] && rate == 1.0f;

    if (replace) {
        [PRMDebug noteAction:@"speed"];
        %orig(chosen, callsite);
        return;
    }
    %orig;
}

%end
