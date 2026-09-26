// Opens PrimeSenger from the sparkles in Messenger's settings bar, since that
// screen is a split-view container with no table rows to add to.

#import "PSGSettings.h"
#import "PRMDebug.h"

%hook MSGSettingsViewController

- (void)viewDidLoad {
    %orig;
    [PRMDebug noteHook:@"settings screen"];

    UIViewController *host = (UIViewController *)self;
    if (![host isKindOfClass:[UIViewController class]]) return;

    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                        weight:UIImageSymbolWeightSemibold];
    UIImage *glyph = [UIImage systemImageNamed:@"sparkles" withConfiguration:configuration];

    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:glyph
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(psg_openSettings)];
    item.tintColor = [UIColor labelColor];
    item.accessibilityLabel = @"PrimeSenger";
    host.navigationItem.rightBarButtonItem = item;
    [PRMDebug log:@"settings entry attached"];
}

%new
- (void)psg_openSettings {
    UIViewController *host = (UIViewController *)self;
    [PRMDebug noteAction:@"settings screen"];
    [host presentViewController:[PSGSettingsViewController presentable]
                       animated:YES
                     completion:nil];
}

%end
