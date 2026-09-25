// Screenshot and recording notices from the disappearing photo viewer and
// the full-screen media viewer.

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

// The full-screen media viewer, which has the same two handlers.
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
