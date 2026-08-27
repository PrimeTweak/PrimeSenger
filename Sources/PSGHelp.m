// Bottom sheet listing what each control in a group does.
//
// Only the detents introduced in iOS 15 are used. A detent sized to the
// sheet's own content needs the resolver added in iOS 16, which is not
// verified against this build's SDK, so a short group opens at the medium
// height rather than hugging its text.

#import "PSGHelp.h"

static const CGFloat kTitleSize     = 17.0;
static const CGFloat kItemTitleSize = 15.0;
static const CGFloat kDetailSize    = 13.5;
static const CGFloat kSideInset     = 20.0;
static const CGFloat kItemInset     = 14.0;
static const CGFloat kTitleInset    = 13.0;
static const CGFloat kTitleGap      = 3.0;
static const CGFloat kBottomInset   = 24.0;
static const CGFloat kCornerRadius  = 12.0;

@interface PSGHelpSheet ()
@property (nonatomic, copy) NSString *sheetTitle;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *items;
@end

@implementation PSGHelpSheet

#pragma mark - Presentation

+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
              items:(NSArray<NSArray<NSString *> *> *)items {
    if (host == nil || items.count == 0) return;

    PSGHelpSheet *sheet = [[PSGHelpSheet alloc] init];
    sheet.sheetTitle = title;
    sheet.items = items;

    UISheetPresentationController *presentation = sheet.sheetPresentationController;
    if (presentation != nil) {
        presentation.prefersGrabberVisible = YES;
        presentation.preferredCornerRadius = kCornerRadius;
        presentation.detents = @[[UISheetPresentationControllerDetent mediumDetent],
                                 [UISheetPresentationControllerDetent largeDetent]];
    }

    [host presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Construction

- (UILabel *)labelWithText:(NSString *)text
                      size:(CGFloat)size
                    weight:(UIFontWeight)weight
                     color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

// One entry: the control's label, the sentence under it, and a hairline
// above every entry but the first.
- (UIView *)entryForItem:(NSArray<NSString *> *)item separated:(BOOL)separated {
    UIView *entry = [[UIView alloc] initWithFrame:CGRectZero];
    entry.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [self labelWithText:item.firstObject
                                    size:kItemTitleSize
                                  weight:UIFontWeightSemibold
                                   color:[UIColor labelColor]];
    UILabel *detail = [self labelWithText:(item.count > 1 ? item[1] : @"")
                                     size:kDetailSize
                                   weight:UIFontWeightRegular
                                    color:[UIColor secondaryLabelColor]];
    [entry addSubview:title];
    [entry addSubview:detail];

    NSMutableArray<NSLayoutConstraint *> *rules = [NSMutableArray arrayWithArray:@[
        [title.topAnchor constraintEqualToAnchor:entry.topAnchor constant:kItemInset],
        [title.leadingAnchor constraintEqualToAnchor:entry.leadingAnchor constant:kSideInset],
        [title.trailingAnchor constraintEqualToAnchor:entry.trailingAnchor constant:-kSideInset],
        [detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:kTitleGap],
        [detail.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [detail.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [detail.bottomAnchor constraintEqualToAnchor:entry.bottomAnchor constant:-kItemInset],
    ]];

    if (separated) {
        UIView *hairline = [[UIView alloc] initWithFrame:CGRectZero];
        hairline.translatesAutoresizingMaskIntoConstraints = NO;
        hairline.backgroundColor = [UIColor separatorColor];
        [entry addSubview:hairline];
        [rules addObjectsFromArray:@[
            [hairline.topAnchor constraintEqualToAnchor:entry.topAnchor],
            [hairline.leadingAnchor constraintEqualToAnchor:entry.leadingAnchor
                                                   constant:kSideInset],
            [hairline.trailingAnchor constraintEqualToAnchor:entry.trailingAnchor],
            [hairline.heightAnchor constraintEqualToConstant:
                1.0 / MAX(UIScreen.mainScreen.scale, 1.0)],
        ]];
    }

    [NSLayoutConstraint activateConstraints:rules];
    return entry;
}

- (UIView *)titleBar {
    UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [self labelWithText:self.sheetTitle
                                    size:kTitleSize
                                  weight:UIFontWeightSemibold
                                   color:[UIColor labelColor]];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    [bar addSubview:label];

    UIView *hairline = [[UIView alloc] initWithFrame:CGRectZero];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    hairline.backgroundColor = [UIColor separatorColor];
    [bar addSubview:hairline];

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:bar.topAnchor constant:kTitleInset],
        [label.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:kSideInset],
        [label.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-kSideInset],
        [label.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-kTitleInset],
        [hairline.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [hairline.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [hairline.heightAnchor constraintEqualToConstant:
            1.0 / MAX(UIScreen.mainScreen.scale, 1.0)],
    ]];
    return bar;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UIView *bar = [self titleBar];
    [self.view addSubview:bar];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 0.0;
    [scroll addSubview:stack];

    for (NSUInteger i = 0; i < self.items.count; i++) {
        [stack addArrangedSubview:[self entryForItem:self.items[i] separated:(i > 0)]];
    }

    // The bottom inset is an arranged view rather than a content inset, so
    // it is included in the scrollable height.
    UIView *tail = [[UIView alloc] initWithFrame:CGRectZero];
    tail.translatesAutoresizingMaskIntoConstraints = NO;
    [tail.heightAnchor constraintEqualToConstant:kBottomInset].active = YES;
    [stack addArrangedSubview:tail];

    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [scroll.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
}

@end
