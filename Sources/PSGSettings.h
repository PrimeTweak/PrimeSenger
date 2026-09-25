// The settings screen, drawn to the metrics of Messenger's own. A noun title
// shows the thing, so its switch is on while the thing is visible; a verb
// title makes something happen. Stored keys never change meaning.

#import <UIKit/UIKit.h>

@interface PSGSettingsViewController : UITableViewController

// Wraps the screen in a navigation controller ready to present.
+ (UIViewController *)presentable;

@end
