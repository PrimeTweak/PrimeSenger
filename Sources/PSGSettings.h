// The settings screen, drawn to the metrics of Messenger's own. A noun title
// shows the thing, so its switch is on while the thing is visible; a verb
// title makes something happen. Stored keys never change meaning.

#import <UIKit/UIKit.h>

@interface PSGSettingsViewController : UITableViewController

// Wraps the screen in a navigation controller ready to present.
+ (UIViewController *)presentable;

@end

// The native pieces every PrimeSenger screen is built from.
@interface PSGSettingsCell : UITableViewCell
@property (nonatomic, strong) UIImageView *glyph;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UIButton *pill;
@property (nonatomic, strong) UILabel *value;
// Resets the cell to a plain row with the given icon and title.
- (void)prepareWithTitle:(NSString *)title symbol:(NSString *)symbol;
@end

@interface PSGSettingsHeader : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIButton *info;
@end

FOUNDATION_EXPORT NSString *const PSGSettingsCellIdentifier;

// Row height, separator inset and cell registration.
FOUNDATION_EXPORT void PSGStyleTable(UITableView *table);
// The card behind each row, rounded only on the edges of its group.
FOUNDATION_EXPORT void PSGApplyCard(UITableView *table, UITableViewCell *cell, NSIndexPath *path);
// A section heading; the info button shows only when a handler is given.
FOUNDATION_EXPORT PSGSettingsHeader *PSGHeader(NSString *title, id target, SEL infoAction, NSInteger tag);
FOUNDATION_EXPORT CGFloat PSGHeaderHeight(NSInteger section, NSString *title);
// The black checkmark used to close a screen, which iOS 26 cannot wash out.
FOUNDATION_EXPORT UIBarButtonItem *PSGCloseItem(id target, SEL action);
