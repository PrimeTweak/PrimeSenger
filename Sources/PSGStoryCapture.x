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

#pragma mark - The media viewer

// Measured on 575: the fullscreen media viewer has the same two handlers as
// the ephemeral one, and they were never covered. _didCaptureContent is 14
// instructions with no calls, the screen recording state change is the one
// that reaches the network.
//
//   -[LSMediaViewerViewController _didCaptureContent]              v16@0:8
//   -[LSMediaViewerViewController _screenCaptureStateDidChange:]   v24@0:8@16
%hook LSMediaViewerViewController

- (void)_didCaptureContent {
    [PRMDebug noteHook:@"screenshot viewer"];
    if ([PRMPrefs isEnabled:PRMKeyBlockScreenshotNotice]) {
        [PRMDebug noteAction:@"screenshot viewer"];
        [PRMDebug setStatus:@"viewer capture swallowed" forKey:@"screenshot viewer"];
        return;
    }
    %orig;
}

- (void)_screenCaptureStateDidChange:(id)note {
    [PRMDebug noteHook:@"screenshot viewer"];
    if ([PRMPrefs isEnabled:PRMKeyBlockScreenshotNotice]) {
        [PRMDebug noteAction:@"screenshot viewer"];
        [PRMDebug setStatus:@"viewer recording state swallowed" forKey:@"screenshot viewer"];
        return;
    }
    %orig;
}

%end
