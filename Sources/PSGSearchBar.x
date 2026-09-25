// Replaces "Ask Meta AI or search" in the inbox search field with "Search".
// The text reaches the bar through its placeholder setter, which is where it
// is swapped.

#import "PRMPrefs.h"
#import "PRMDebug.h"
#import <UIKit/UIKit.h>

%hook MSGUniversalUISearchBar

- (void)setPlaceholder:(NSString *)placeholder {
    [PRMDebug noteHook:@"search bar setter"];
    if ([PRMPrefs isEnabled:PRMKeyHideMetaAI] && [placeholder isKindOfClass:[NSString class]]) {
        [PRMDebug noteAction:@"search bar setter"];
        %orig(@"Search");
        return;
    }
    %orig;
}

%end
