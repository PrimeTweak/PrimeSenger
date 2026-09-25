// The sheet behind a section's info button: one entry per option whose title
// needs explaining, each with its icon, its title and a plain sentence.

#import <UIKit/UIKit.h>

@interface PSGHelpSheet : UIViewController

// Each item is @[title, text] or @[title, text, symbol name].
+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
              items:(NSArray<NSArray<NSString *> *> *)items;

@end
