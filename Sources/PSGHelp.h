// Help sheet for a settings group.
//
// Each group carries a "?" that opens this: one entry per control in the
// group, each with a plain sentence describing what that control does.
// Presentation only. The sentences live beside the rows they describe, in
// the settings screen, so the two cannot drift apart.

#import <UIKit/UIKit.h>

@interface PSGHelpSheet : UIViewController

// Items are pairs: the control's own label, then its description. Nothing
// is presented when the list is empty.
+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
              items:(NSArray<NSArray<NSString *> *> *)items;

@end
