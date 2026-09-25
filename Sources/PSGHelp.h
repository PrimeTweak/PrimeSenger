// The sheet behind an option's info button: its title and one or two plain
// sentences on what the option does.

#import <UIKit/UIKit.h>

@interface PSGHelpSheet : UIViewController

// Items are pairs: the control's own label, then its description. Nothing
// is presented when the list is empty.
+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
              items:(NSArray<NSArray<NSString *> *> *)items;

@end
