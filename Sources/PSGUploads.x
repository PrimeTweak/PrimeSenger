// HD uploads.
//
// The picker owns its own toggle and its own tap handler. Measured on this
// build of Messenger:
//
//   hd state   toggle:36x36 persist=0            at viewDidAppear, not selected
//   hd tap     before:36x36 sel -> after:36x36   sender=MDSIconButton, persist=1
//
// So the selected property of the button is the state, and the host's own
// handler takes the button as its sender. The state is read before anything
// is pressed, which is what keeps an already enabled toggle from being
// flipped back off.
//
//   -[LSMediaPickerViewController viewDidAppear:]    v20@0:8B16
//   -[LSMediaPickerViewController _didTapHDToggle:]  v24@0:8@16
//   ivar _hdToggleButton : UIButton
//   ivar _shouldPersistHdToggleState : B
//
// Note that this only reaches uploads going through the app's own picker.
// When the photo library permission is missing the app hands over to the
// system picker, which carries no HD control.

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


// The View once control in the picker. Measured on 575:
//
//   _didTapViewOnceToggle                    v16@0:8      14 instructions, 6 calls
//   viewOnceToggleTapHandlerWithIsToggleOn:  v20@0:8B16
//
// Both are covered: the tap is swallowed, and the handler is forced to NO in
// case the host reaches it another way. Which one fired is recorded.
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
