#import "AIProfileListViewController.h"
#import "AISettings.h"

@implementation AIProfileListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UILabel *empty = [[UILabel alloc] initWithFrame:CGRectZero];
    empty.text = @"还没有学习的风格档案\n在聊天信息页点“学习聊天风格”即可创建";
    empty.numberOfLines = 0;
    empty.textAlignment = NSTextAlignmentCenter;
    empty.textColor = [UIColor secondaryLabelColor];
    empty.font = [UIFont systemFontOfSize:14];
    self.tableView.backgroundView = empty;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSInteger count = [AISettings styleProfileCount];
    self.title = count > 0 ? [NSString stringWithFormat:@"学习档案（%ld）", (long)count] : @"学习档案";
    self.tableView.backgroundView.hidden = count > 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [AISettings styleProfileCount];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ProfileCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"ProfileCell"];
    }
    NSArray *profiles = [AISettings allStyleProfiles];
    if (indexPath.row < profiles.count) {
        NSDictionary *item = profiles[indexPath.row];
        cell.textLabel.text = item[@"chatId"];
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        NSString *preview = item[@"profile"];
        if (preview.length > 80) preview = [preview substringToIndex:80];
        cell.detailTextLabel.text = preview;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.numberOfLines = 2;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                            forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSArray *profiles = [AISettings allStyleProfiles];
    if (indexPath.row < profiles.count) {
        [AISettings clearStyleProfileForChat:profiles[indexPath.row][@"chatId"]];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        NSInteger count = [AISettings styleProfileCount];
        self.title = count > 0 ? [NSString stringWithFormat:@"学习档案（%ld）", (long)count] : @"学习档案";
        self.tableView.backgroundView.hidden = count > 0;
    }
}

@end
