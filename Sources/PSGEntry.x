// Entry point into the tweak's settings.
//
// MSGSettingsViewController is a split-view container and exposes no table
// methods, so the entry point is a navigation bar button rather than a row.
// The glyph matches the weight of the bar's other items.
//
// Signature taken from the binary:
//   -[MSGSettingsViewController viewDidLoad]  v16@0:8

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
    UIImage *bolt = [UIImage systemImageNamed:@"bolt.fill" withConfiguration:configuration];

    UIBarButtonItem *item;
    if (bolt != nil) {
        item = [[UIBarButtonItem alloc] initWithImage:bolt
                                                style:UIBarButtonItemStylePlain
                                               target:self
                                               action:@selector(psg_openSettings)];
        item.tintColor = [UIColor labelColor];
    } else {
        // Never leave the screen without a way in.
        [PRMDebug log:@"bolt.fill unavailable, falling back to text"];
        item = [[UIBarButtonItem alloc] initWithTitle:@"PrimeSenger"
                                                style:UIBarButtonItemStylePlain
                                               target:self
                                               action:@selector(psg_openSettings)];
    }
    item.accessibilityLabel = @"PrimeSenger";
    host.navigationItem.rightBarButtonItem = item;
    [PRMDebug log:@"settings entry attached as %@", bolt ? @"bolt" : @"text"];
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
