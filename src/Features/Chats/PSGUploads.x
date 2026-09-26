// HD uploads: the picker's own toggle is switched on when it opens, unless
// it is already on.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

%hook LSMediaPickerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [PRMDebug noteHook:@"hd uploads"];
    if (![PRMPrefs isEnabled:PRMKeyUploadHD]) return;

    id picker = self;
    Ivar slot = class_getInstanceVariable(object_getClass(picker), "_hdToggleButton");
    UIButton *toggle = slot ? object_getIvar(picker, slot) : nil;
    if (![toggle isKindOfClass:[UIButton class]]) {
        [PRMDebug setStatus:@"toggle unavailable" forKey:@"hd uploads"];
        return;
    }

    if (toggle.selected) {
        [PRMDebug setStatus:@"already on" forKey:@"hd uploads"];
        return;
    }
    if (![picker respondsToSelector:@selector(_didTapHDToggle:)]) {
        [PRMDebug setStatus:@"tap handler missing" forKey:@"hd uploads"];
        return;
    }

    [PRMDebug noteAction:@"hd uploads"];
    ((void (*)(id, SEL, id))objc_msgSend)(picker, @selector(_didTapHDToggle:), toggle);

    [PRMDebug setStatus:toggle.selected ? @"turned on" : @"tap left it off"
                 forKey:@"hd uploads"];
}


// The View once control: the tap is swallowed, and its handler is forced
// off in case the host reaches it another way.
- (void)_didTapViewOnceToggle {
    [PRMDebug noteHook:@"view once send"];
    if ([PRMPrefs isEnabled:PRMKeyBlockViewOnceSend]) {
        [PRMDebug noteAction:@"view once send"];
        [PRMDebug setStatus:@"tap swallowed" forKey:@"view once send"];
        return;
    }
    %orig;
}

- (void)viewOnceToggleTapHandlerWithIsToggleOn:(BOOL)on {
    [PRMDebug noteHook:@"view once send"];
    if ([PRMPrefs isEnabled:PRMKeyBlockViewOnceSend] && on) {
        [PRMDebug noteAction:@"view once send"];
        [PRMDebug setStatus:@"handler forced off" forKey:@"view once send"];
        %orig(NO);
        return;
    }
    %orig;
}

%end
