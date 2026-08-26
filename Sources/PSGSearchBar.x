// The inbox search placeholder, which reads "Ask Meta AI or search".
// Signatures taken from the binary:
//   -[MSGSearchBarPlaceholderProvider defaultPlaceholder]   @16@0:8
//   -[MSGSearchBarPlaceholderProvider currentPlaceholder]   @16@0:8
//   -[MSGSearchBarPlaceholderProvider moveNextPlaceholder]  @16@0:8
//
// The return type is only known to be an object. Each hook therefore
// inspects what the original returned: a string is replaced, anything
// else is logged and passed through untouched.

#import "PRMPrefs.h"
#import "PRMDebug.h"

static id PRMPlainPlaceholder(id original, NSString *site) {
    if (![PRMPrefs isEnabled:PRMKeyHideMetaAI]) return original;

    if ([original isKindOfClass:[NSString class]]) {
        [PRMDebug noteAction:@"search placeholder"];
        return @"Search";
    }
    if ([original isKindOfClass:[NSAttributedString class]]) {
        [PRMDebug noteAction:@"search placeholder"];
        return [[NSAttributedString alloc] initWithString:@"Search"];
    }
    [PRMDebug log:@"placeholder %@ is %@, left untouched",
                  site, NSStringFromClass([original class])];
    return original;
}

%hook MSGSearchBarPlaceholderProvider

- (id)defaultPlaceholder {
    [PRMDebug noteHook:@"search placeholder"];
    id original = %orig;
    return PRMPlainPlaceholder(original, @"default");
}

- (id)currentPlaceholder {
    [PRMDebug noteHook:@"search placeholder"];
    id original = %orig;
    return PRMPlainPlaceholder(original, @"current");
}

- (id)moveNextPlaceholder {
    [PRMDebug noteHook:@"search placeholder"];
    id original = %orig;
    return PRMPlainPlaceholder(original, @"next");
}

%end
