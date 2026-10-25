// The tabs PrimeSenger removes from Messenger's bar, one switch per tab.

#import <UIKit/UIKit.h>

@interface PSGHiddenTabsViewController : UITableViewController
@end

// The hidden tabs by name, or "None", for the row that opens this screen.
FOUNDATION_EXPORT NSString *PSGHiddenTabsSummary(void);
