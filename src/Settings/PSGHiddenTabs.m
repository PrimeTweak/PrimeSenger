#import "PSGHiddenTabs.h"
#import "PSGSettings.h"
#import "PRMPrefs.h"
#import "PRMDebug.h"

// Messenger's tabs in bar order, each with the key that hides it.
static NSArray<NSArray<NSString *> *> *PSGTabs(void) {
    return @[
        @[@"Chats",         @"bubble.left.fill",     PRMKeyHideTabChats],
        @[@"Meta AI",       @"circle.circle.fill",   PRMKeyHideTabMetaAI],
        @[@"Stories",       @"play.rectangle.fill",  PRMKeyHideTabStories],
        @[@"Notifications", @"bell.badge.fill",      PRMKeyHideTabNotifications],
        @[@"Menu",          @"line.3.horizontal",    PRMKeyHideTabMenu],
    ];
}

NSString *PSGHiddenTabsSummary(void) {
    NSMutableArray<NSString *> *hidden = [NSMutableArray array];
    for (NSArray<NSString *> *tab in PSGTabs()) {
        if ([PRMPrefs isEnabled:tab[2]]) [hidden addObject:tab[0]];
    }
    return hidden.count ? [hidden componentsJoinedByString:@", "] : @"None";
}

@implementation PSGHiddenTabsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Hidden tabs";
    PSGStyleTable(self.tableView);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)PSGTabs().count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return PSGHeader(@"Tabs", nil, NULL, 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return PSGHeaderHeight(section, @"Tabs");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Takes effect after a restart.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSString *> *tab = PSGTabs()[(NSUInteger)indexPath.row];
    PSGSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:PSGSettingsCellIdentifier
                                                            forIndexPath:indexPath];
    [cell prepareWithTitle:tab[0] symbol:tab[1]];
    cell.accessoryView = cell.toggle;
    cell.toggle.on = [PRMPrefs isEnabled:tab[2]];
    cell.toggle.tag = indexPath.row;
    [cell.toggle addTarget:self action:@selector(toggleChanged:)
          forControlEvents:UIControlEventValueChanged];
    return cell;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGApplyCard(tableView, cell, indexPath);
}

- (void)toggleChanged:(UISwitch *)toggle {
    NSArray<NSString *> *tab = PSGTabs()[(NSUInteger)toggle.tag];
    [PRMPrefs setEnabled:toggle.on forKey:tab[2]];
    [PRMDebug refreshFloatingButton];
    [PRMDebug returnButtonToSlot];
    if (toggle.on && [tab[2] isEqualToString:PRMKeyHideTabMenu]) [self noteMenuTabHidden];
}

// Settings live under the Menu tab, so hiding it says where they went. Shown
// every time, since it is the only way back into PrimeSenger.
- (void)noteMenuTabHidden {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Menu tab hidden"
                         message:@"PrimeSenger settings now open from the floating button. "
                                  "The tab disappears once Messenger restarts."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
