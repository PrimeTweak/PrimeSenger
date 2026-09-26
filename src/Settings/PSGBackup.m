#import "PSGBackup.h"
#import "PSGSettings.h"
#import "PSGHelp.h"
#import "PRMDebug.h"

static NSString *const kPSGPrefix = @"psg_";
static NSString *const kPSGAutoClear = @"psg_cache_autoclear";
static NSString *const kPSGLastClear = @"psg_cache_last_cleared";

static NSArray<NSString *> *PSGAutoClearTitles(void) {
    return @[@"Off", @"At launch", @"Daily", @"Weekly"];
}

#pragma mark - Cache

static unsigned long long PSGSizeOf(NSURL *url) {
    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    if (!isDirectory.boolValue) {
        NSNumber *size = nil;
        [url getResourceValue:&size forKey:NSURLTotalFileAllocatedSizeKey error:nil];
        return size.unsignedLongLongValue;
    }
    unsigned long long total = 0;
    NSDirectoryEnumerator *walk = [[NSFileManager defaultManager]
        enumeratorAtURL:url includingPropertiesForKeys:@[NSURLTotalFileAllocatedSizeKey]
                options:0 errorHandler:nil];
    for (NSURL *item in walk) {
        NSNumber *size = nil;
        [item getResourceValue:&size forKey:NSURLTotalFileAllocatedSizeKey error:nil];
        total += size.unsignedLongLongValue;
    }
    return total;
}

static NSString *PSGSizeText(unsigned long long bytes) {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

// The only folders of Library/Caches that are cleared: logs, crash and
// performance reports, network and web caches. Any other folder is never touched.
static NSArray<NSString *> *PSGClearableFolders(void) {
    return @[@"Logs", @"FeatureLogs", @"RsysLogs", @"BreakpadAssertions", @"BreakpadStalls",
             @"Sanitizer", @"qpl_crash_resilient", @"MNSDNSCacheV2", @"MNSResumptionCacheV2",
             @"DGWMnsCache", @"OhaiMnsCache", @"WebKit", @"com.apple.WebKit.Networking",
             @"com.apple.nsurlsessiond"];
}

@implementation PSGCache

+ (NSURL *)temporary {
    return [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
}

// The folders to empty: the listed cache folders that exist, and tmp.
+ (NSArray<NSURL *> *)folders {
    NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
    NSMutableArray<NSURL *> *folders = [NSMutableArray arrayWithObject:[self temporary]];
    for (NSString *name in PSGClearableFolders()) {
        NSURL *folder = [caches URLByAppendingPathComponent:name isDirectory:YES];
        if ([folder checkResourceIsReachableAndReturnError:nil]) [folders addObject:folder];
    }
    return folders;
}

// The network cache lives in the app's own cache folder, whose database stays
// open, so it is emptied through NSURLCache rather than deleted on disk.
+ (unsigned long long)clearableBytes {
    unsigned long long total = (unsigned long long)NSURLCache.sharedURLCache.currentDiskUsage;
    for (NSURL *folder in [self folders]) total += PSGSizeOf(folder);
    return total;
}

// Each folder is emptied, not removed, so whatever writes into it still finds it.
+ (void)clear {
    [NSURLCache.sharedURLCache removeAllCachedResponses];
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSURL *folder in [self folders]) {
        for (NSURL *item in [files contentsOfDirectoryAtURL:folder
                                 includingPropertiesForKeys:nil options:0 error:nil]) {
            [files removeItemAtURL:item error:nil];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kPSGLastClear];
    [PRMDebug noteAction:@"cache cleared"];
}

+ (void)clearIfDue {
    NSInteger interval = [[NSUserDefaults standardUserDefaults] integerForKey:kPSGAutoClear];
    if (interval <= 0) return;
    NSDate *last = [[NSUserDefaults standardUserDefaults] objectForKey:kPSGLastClear];
    NSTimeInterval since = last ? -[last timeIntervalSinceNow] : DBL_MAX;
    NSTimeInterval wanted = interval == 2 ? 86400.0 : (interval == 3 ? 604800.0 : 0.0);
    if (since >= wanted) [self clear];
}

@end

#pragma mark - Auto-clear

@interface PSGAutoClearViewController : UITableViewController
@end

@implementation PSGAutoClearViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Auto-clear";
    PSGStyleTable(self.tableView);
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 18.0, 0.0, 0.0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)PSGAutoClearTitles().count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return PSGHeader(@"Clear the cache", nil, NULL, 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return PSGHeaderHeight(section, @"Clear the cache");
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:PSGSettingsCellIdentifier
                                                            forIndexPath:indexPath];
    [cell prepareWithTitle:PSGAutoClearTitles()[(NSUInteger)indexPath.row] symbol:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    NSInteger chosen = [[NSUserDefaults standardUserDefaults] integerForKey:kPSGAutoClear];
    cell.accessoryType = indexPath.row == chosen ? UITableViewCellAccessoryCheckmark
                                                 : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGApplyCard(tableView, cell, indexPath);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [[NSUserDefaults standardUserDefaults] setInteger:indexPath.row forKey:kPSGAutoClear];
    [tableView reloadData];
}

@end

#pragma mark - Backup & reset

@interface PSGBackupViewController () <UIDocumentPickerDelegate>
@end

@implementation PSGBackupViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Backup & reset";
    PSGStyleTable(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 2 ? 1 : 2;
}

- (NSString *)titleForSection:(NSInteger)section {
    return @[@"Backup", @"Cache", @"Reset"][(NSUInteger)section];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return PSGHeader([self titleForSection:section], self,
                     section == 1 ? @selector(showCacheHelp) : NULL, section);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return PSGHeaderHeight(section, [self titleForSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (void)showCacheHelp {
    [PSGHelpSheet presentFrom:self title:@"Cache" items:@[
        @[@"Clear cache",
          @"Removes Messenger's logs, crash reports, network caches and temporary files. Your "
           "chats, media and settings stay.",
          @"trash.fill"],
        @[@"Auto-clear", @"Clears the cache when Messenger starts, at the interval you pick.",
          @"clock.fill"],
    ]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGSettingsCell *cell = [tableView dequeueReusableCellWithIdentifier:PSGSettingsCellIdentifier
                                                            forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (indexPath.section == 0) {
        [cell prepareWithTitle:(indexPath.row == 0 ? @"Import settings" : @"Export settings")
                        symbol:(indexPath.row == 0 ? @"square.and.arrow.down.fill"
                                                   : @"square.and.arrow.up.fill")];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        [cell prepareWithTitle:@"Clear cache" symbol:@"trash.fill"];
        cell.value.text = PSGSizeText([PSGCache clearableBytes]);
        cell.value.hidden = NO;
    } else if (indexPath.section == 1) {
        [cell prepareWithTitle:@"Auto-clear" symbol:@"clock.fill"];
        NSInteger chosen = [[NSUserDefaults standardUserDefaults] integerForKey:kPSGAutoClear];
        cell.value.text = PSGAutoClearTitles()[(NSUInteger)MAX(0, MIN(chosen, 3))];
        cell.value.hidden = NO;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        [cell prepareWithTitle:@"Reset to defaults" symbol:@"arrow.counterclockwise"];
        cell.label.textColor = [UIColor systemRedColor];
        cell.glyph.tintColor = [UIColor systemRedColor];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSGApplyCard(tableView, cell, indexPath);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) [self importSettings];
        else [self exportSettings];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        [self confirmClear];
    } else if (indexPath.section == 1) {
        [self.navigationController pushViewController:
            [[PSGAutoClearViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]
                                             animated:YES];
    } else {
        [self confirmReset];
    }
}

// Every PrimeSenger preference, read straight from the defaults by prefix.
- (NSDictionary *)currentSettings {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *key in all) {
        if (![key hasPrefix:kPSGPrefix] || [key isEqualToString:kPSGLastClear]) continue;
        id value = all[key];
        if ([NSJSONSerialization isValidJSONObject:@[value]]) settings[key] = value;
    }
    return settings;
}

- (void)exportSettings {
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self currentSettings]
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"PrimeSenger-Settings.json"];
    if (data == nil || ![data writeToFile:path atomically:YES]) {
        [self tell:@"Export failed" message:@"The settings could not be written."];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    [self presentViewController:share animated:YES completion:nil];
}

- (void)importSettings {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.json"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSData *data = urls.firstObject ? [NSData dataWithContentsOfURL:urls.firstObject] : nil;
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) {
        [self tell:@"Import failed" message:@"This file is not a PrimeSenger settings export."];
        return;
    }
    NSUInteger applied = 0;
    for (NSString *key in (NSDictionary *)json) {
        if (![key isKindOfClass:[NSString class]] || ![key hasPrefix:kPSGPrefix]) continue;
        [[NSUserDefaults standardUserDefaults] setObject:json[key] forKey:key];
        applied++;
    }
    [self.tableView reloadData];
    [self tell:@"Settings imported"
       message:[NSString stringWithFormat:@"%lu settings restored. Restart Messenger to apply them all.",
                (unsigned long)applied]];
}

- (void)confirmClear {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Clear cache"
                         message:@"Removes logs, crash reports, network caches and temporary files. "
                                  "Your chats, media and settings stay."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [PSGCache clear];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset to defaults"
                         message:@"Turns every option back to Messenger's own behavior. Restart Messenger afterwards."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        for (NSString *key in [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]) {
            if ([key hasPrefix:kPSGPrefix]) [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
        }
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tell:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
