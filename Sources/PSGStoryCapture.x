// Screenshot handling for the story viewer. This lives on the ephemeral
// media controller, not on the application object: MSGApplication exposes
// no handler at all in this build.
// Signatures taken from the binary:
//   -[MSGEphemeralMediaViewController _didCaptureContent]            v16@0:8
//   -[MSGEphemeralMediaViewController _screenCaptureStateDidChange:]  v24@0:8@16

#import "PRMPrefs.h"
#import "PRMDebug.h"

%hook MSGEphemeralMediaViewController

- (void)_didCaptureContent {
    [PRMDebug noteHook:@"screenshot notice"];
    if ([PRMPrefs isEnabled:PRMKeyBlockScreenshotNotice]) {
        [PRMDebug noteAction:@"screenshot notice"];
        [PRMDebug log:@"screenshot notice suppressed"];
        return;
    }
    %orig;
}

- (void)_screenCaptureStateDidChange:(id)notification {
    [PRMDebug noteHook:@"screen capture state"];
    if ([PRMPrefs isEnabled:PRMKeyBlockScreenshotNotice]) {
        [PRMDebug noteAction:@"screen capture state"];
        return;
    }
    %orig;
}

%end
