#import "PRMSuppress.h"
#import "PRMPrefs.h"

@implementation PRMSuppress

+ (NSDictionary<NSString *, NSString *> *)rules {
    static NSDictionary *rules = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        // Fragment of a controller class name -> the switch that hides it.
        rules = @{
            @"MetaAIFAB"        : PRMKeyHideMetaAIButton,
            @"InboxTray"        : PRMKeyHideStoriesTray,
            @"PYMK"             : PRMKeyHidePeopleYouMayKnow,
            @"PeopleYouMayKnow" : PRMKeyHidePeopleYouMayKnow,
        };
    });
    return rules;
}

+ (NSString *)keyForControllerName:(NSString *)name {
    if (name.length == 0) return nil;
    NSDictionary *rules = [self rules];
    for (NSString *fragment in rules) {
        NSRange found = [name rangeOfString:fragment
                                    options:NSCaseInsensitiveSearch];
        if (found.location != NSNotFound) return rules[fragment];
    }
    return nil;
}

+ (BOOL)shouldSuppressControllerName:(NSString *)name {
    // One switch neutralises every removal without disturbing the others,
    // so the interface can be restored whole in a single gesture.
    if ([PRMPrefs isEnabled:PRMKeyMasterDisable]) return NO;
    NSString *key = [self keyForControllerName:name];
    if (key == nil) return NO;
    return [PRMPrefs isEnabled:key];
}

@end
