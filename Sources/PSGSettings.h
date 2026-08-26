// The tweak's settings screen, built to the metrics of Messenger's own:
// no section titles, single-line rows 52pt tall, a filled glyph at the
// leading edge, and separators inset to where the text starts.
//
// Labels name the thing rather than the action, matching every native row.
// A switch therefore reads as "this is present", so preferences whose
// stored meaning is "hide this" are displayed inverted. The stored keys are
// untouched, so nothing already set is lost.

#import <UIKit/UIKit.h>

@interface PSGSettingsViewController : UITableViewController

// Wraps the screen in a navigation controller ready to present.
+ (UIViewController *)presentable;

@end
