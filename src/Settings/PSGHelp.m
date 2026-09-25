#import "PSGHelp.h"

static const CGFloat kPSGHelpTitleTop = 26.0;
static const CGFloat kPSGHelpListGap = 26.0;
static const CGFloat kPSGHelpBottom = 28.0;
static const CGFloat kPSGHelpSideInset = 24.0;

static UIView *PSGHelpRow(NSArray<NSString *> *item) {
    UILabel *name = [[UILabel alloc] init];
    name.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    name.textColor = [UIColor labelColor];
    name.numberOfLines = 0;
    name.text = item[0];

    UILabel *text = [[UILabel alloc] init];
    text.font = [UIFont systemFontOfSize:15.0];
    text.textColor = [UIColor secondaryLabelColor];
    text.numberOfLines = 0;
    text.text = item.count > 1 ? item[1] : @"";

    UIStackView *words = [[UIStackView alloc] initWithArrangedSubviews:@[name, text]];
    words.axis = UILayoutConstraintAxisVertical;
    words.spacing = 3.0;

    UIImage *glyph = nil;
    if (item.count > 2) {
        UIImageSymbolConfiguration *size =
            [UIImageSymbolConfiguration configurationWithPointSize:19.0
                                                            weight:UIImageSymbolWeightSemibold];
        glyph = [UIImage systemImageNamed:item[2] withConfiguration:size];
    }
    UIImageView *icon = [[UIImageView alloc] initWithImage:glyph];
    icon.tintColor = [UIColor labelColor];
    icon.contentMode = UIViewContentModeCenter;
    icon.hidden = glyph == nil;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:24.0].active = YES;
    [icon.heightAnchor constraintEqualToConstant:24.0].active = YES;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, words]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentTop;
    row.spacing = 16.0;
    return row;
}

@implementation PSGHelpSheet {
    NSString *_sheetTitle;
    NSArray<NSArray<NSString *> *> *_items;
    UILabel *_titleLabel;
    UIStackView *_list;
}

+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
              items:(NSArray<NSArray<NSString *> *> *)items {
    if (host == nil || items.count == 0) return;
    PSGHelpSheet *sheet = [[PSGHelpSheet alloc] initWithNibName:nil bundle:nil];
    sheet->_sheetTitle = [title copy];
    sheet->_items = [items copy];
    sheet.modalPresentationStyle = UIModalPresentationPageSheet;

    // The fitted height needs iOS 16; older systems fall back to the medium detent.
    UISheetPresentationController *controller = sheet.sheetPresentationController;
    CGFloat width = host.view.bounds.size.width;
    if (@available(iOS 16.0, *)) {
        __weak PSGHelpSheet *weakSheet = sheet;
        controller.detents = @[[UISheetPresentationControllerDetent
            customDetentWithIdentifier:@"PSGHelpSheet"
                              resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                return MIN([weakSheet fittingHeightForWidth:width], context.maximumDetentValue);
            }]];
    } else {
        controller.detents = @[[UISheetPresentationControllerDetent mediumDetent]];
    }
    controller.prefersGrabberVisible = YES;
    [host presentViewController:sheet animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.text = _sheetTitle;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *symbol =
        [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightSemibold];
    [close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:symbol]
           forState:UIControlStateNormal];
    close.tintColor = [UIColor labelColor];
    close.backgroundColor = [UIColor tertiarySystemFillColor];
    close.layer.cornerRadius = 20.0;
    close.accessibilityLabel = @"Close";
    [close addTarget:self action:@selector(closeSheet) forControlEvents:UIControlEventTouchUpInside];
    close.translatesAutoresizingMaskIntoConstraints = NO;

    _list = [[UIStackView alloc] init];
    _list.axis = UILayoutConstraintAxisVertical;
    _list.spacing = 22.0;
    _list.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSArray<NSString *> *item in _items) [_list addArrangedSubview:PSGHelpRow(item)];

    [self.view addSubview:_titleLabel];
    [self.view addSubview:close];
    [self.view addSubview:_list];
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:kPSGHelpTitleTop],
        [_titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:64.0],
        [close.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [close.widthAnchor constraintEqualToConstant:40.0],
        [close.heightAnchor constraintEqualToConstant:40.0],
        [_list.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:kPSGHelpListGap],
        [_list.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kPSGHelpSideInset],
        [_list.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kPSGHelpSideInset],
    ]];
}

- (void)closeSheet {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (CGFloat)fittingHeightForWidth:(CGFloat)width {
    [self loadViewIfNeeded];
    CGSize list = [_list systemLayoutSizeFittingSize:CGSizeMake(width - 2.0 * kPSGHelpSideInset,
                                                                UILayoutFittingCompressedSize.height)
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return kPSGHelpTitleTop + ceil(_titleLabel.font.lineHeight) + kPSGHelpListGap
         + ceil(list.height) + kPSGHelpBottom;
}

@end
