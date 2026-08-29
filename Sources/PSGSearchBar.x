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
#import <UIKit/UIKit.h>

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

#pragma mark - Placeholder at the bar

// Measured: the three provider methods above have never fired in any report,
// so the text does not come through that class on this build. The bar itself
// carries it. MSGUniversalUISearchBar is a UISearchBar subclass, seen in the
// view tree holding a UISearchBarTextFieldLabel that reads "Ask Meta AI or
// search".
//
// Two points are taken at once: the property setter, which is where a
// placeholder would normally arrive, and the layout pass, which reaches the
// label whatever route the text took. Each reports separately, so one build
// says which one owns the text.

static UILabel *PSGFindPlaceholderLabel(UIView *view, NSInteger depth) {
    if (depth > 6 || view == nil) return nil;
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:[UILabel class]]) {
            NSString *name = NSStringFromClass([child class]);
            if ([name containsString:@"SearchBarTextFieldLabel"]) return (UILabel *)child;
        }
        UILabel *found = PSGFindPlaceholderLabel(child, depth + 1);
        if (found != nil) return found;
    }
    return nil;
}

%hook MSGUniversalUISearchBar

// Inherited from UISearchBar, so the original resolves to the superclass.
- (void)setPlaceholder:(NSString *)placeholder {
    [PRMDebug noteHook:@"search bar setter"];
    [PRMDebug setStatus:placeholder ?: @"nil" forKey:@"search bar setter"];

    if ([PRMPrefs isEnabled:PRMKeyHideMetaAI] && [placeholder isKindOfClass:[NSString class]]) {
        [PRMDebug noteAction:@"search bar setter"];
        %orig(@"Search");
        return;
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;
    [PRMDebug noteHook:@"search bar layout"];

    UILabel *label = PSGFindPlaceholderLabel((UIView *)self, 0);
    if (label == nil) {
        [PRMDebug setStatus:@"label not found" forKey:@"search bar layout"];
        return;
    }

    NSString *text = label.text ?: @"";
    if (![PRMPrefs isEnabled:PRMKeyHideMetaAI]) {
        [PRMDebug setStatus:[NSString stringWithFormat:@"off, reads %@", text]
                     forKey:@"search bar layout"];
        return;
    }

    // Written only when it differs, so a layout pass that changes nothing
    // cannot start another one.
    if ([text containsString:@"Meta AI"]) {
        label.text = @"Search";
        [PRMDebug noteAction:@"search bar layout"];
    }
    [PRMDebug setStatus:[NSString stringWithFormat:@"was %@, now %@", text, label.text ?: @""]
                 forKey:@"search bar layout"];
}

%end
