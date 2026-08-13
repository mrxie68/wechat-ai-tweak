#import "AIProfileEditorViewController.h"
#import "AISettings.h"

@implementation AIProfileEditorViewController {
    NSString *_chatId;
    NSString *_initialProfile;
    NSDictionary *_friendInfo;
    UITextView *_textView;
    UITextField *_callField;
    UITextField *_relationField;
    UISegmentedControl *_favorControl;
    UITextView *_basicView;
    UITextView *_noteView;
}

- (instancetype)initWithChatId:(NSString *)chatId profile:(NSString *)profile {
    self = [super init];
    if (self) {
        _chatId = [chatId copy];
        _initialProfile = [profile copy];
        _friendInfo = [AISettings friendInfoForChat:chatId];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"编辑档案";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(saveTapped)];

    CGFloat w = self.view.bounds.size.width;

    // 对方信息：称呼 / 关系 / 好感度 / 基本情况 / 备注
    UILabel *callLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, 56, 30)];
    callLabel.text = @"称呼";
    callLabel.font = [UIFont systemFontOfSize:15];
    [self.view addSubview:callLabel];
    _callField = [[UITextField alloc] initWithFrame:CGRectMake(78, 12, w - 94, 30)];
    _callField.placeholder = @"如：老张 / 老铁 / 阿凯";
    _callField.font = [UIFont systemFontOfSize:15];
    _callField.borderStyle = UITextBorderStyleRoundedRect;
    _callField.text = _friendInfo[@"call"] ?: @"";
    [self.view addSubview:_callField];

    UILabel *relLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, 56, 30)];
    relLabel.frame = CGRectMake(16, 50, 56, 30);
    relLabel.text = @"关系";
    relLabel.font = [UIFont systemFontOfSize:15];
    [self.view addSubview:relLabel];
    _relationField = [[UITextField alloc] initWithFrame:CGRectMake(78, 50, w - 94, 30)];
    _relationField.placeholder = @"如：好朋友 / 同事 / 家人";
    _relationField.font = [UIFont systemFontOfSize:15];
    _relationField.borderStyle = UITextBorderStyleRoundedRect;
    _relationField.text = _friendInfo[@"relation"] ?: @"";
    [self.view addSubview:_relationField];

    UILabel *favLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 88, 56, 30)];
    favLabel.text = @"好感度";
    favLabel.font = [UIFont systemFontOfSize:15];
    [self.view addSubview:favLabel];
    _favorControl = [[UISegmentedControl alloc] initWithItems:@[@"高", @"中", @"低"]];
    _favorControl.frame = CGRectMake(78, 88, w - 94, 30);
    NSString *fav = _friendInfo[@"favor"] ?: @"中";
    _favorControl.selectedSegmentIndex = [fav isEqualToString:@"高"] ? 0 : ([fav isEqualToString:@"低"] ? 2 : 1);
    [self.view addSubview:_favorControl];

    UILabel *basicLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 126, w - 32, 16)];
    basicLabel.text = @"对方基本情况（工作/家庭/住址，AI 以此为准不编造）";
    basicLabel.font = [UIFont systemFontOfSize:12];
    basicLabel.textColor = [UIColor secondaryLabelColor];
    [self.view addSubview:basicLabel];
    _basicView = [[UITextView alloc] initWithFrame:CGRectMake(16, 146, w - 32, 56)];
    _basicView.font = [UIFont systemFontOfSize:14];
    _basicView.text = _friendInfo[@"basic"] ?: @"";
    _basicView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    _basicView.layer.cornerRadius = 8;
    [self.view addSubview:_basicView];

    UILabel *noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 210, w - 32, 16)];
    noteLabel.text = @"备注（性格/习惯/共同经历/雷区）";
    noteLabel.font = [UIFont systemFontOfSize:12];
    noteLabel.textColor = [UIColor secondaryLabelColor];
    [self.view addSubview:noteLabel];
    _noteView = [[UITextView alloc] initWithFrame:CGRectMake(16, 230, w - 32, 56)];
    _noteView.font = [UIFont systemFontOfSize:14];
    _noteView.text = _friendInfo[@"note"] ?: @"";
    _noteView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    _noteView.layer.cornerRadius = 8;
    [self.view addSubview:_noteView];

    UILabel *profileLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 294, w - 32, 16)];
    profileLabel.text = @"风格档案（AI 学出来的，可修改完善）";
    profileLabel.font = [UIFont systemFontOfSize:12];
    profileLabel.textColor = [UIColor secondaryLabelColor];
    [self.view addSubview:profileLabel];

    _textView = [[UITextView alloc] initWithFrame:CGRectMake(16, 314, w - 32, self.view.bounds.size.height - 326)];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.font = [UIFont systemFontOfSize:15];
    _textView.text = _initialProfile;
    _textView.textContainerInset = UIEdgeInsetsMake(12, 8, 12, 8);
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _textView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    _textView.layer.cornerRadius = 12;
    [self.view addSubview:_textView];
}

- (void)saveTapped {
    NSString *text = [_textView.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        UIAlertController *warn = [UIAlertController alertControllerWithTitle:@"内容为空"
                                                                     message:@"风格档案不能为空，请填写内容。"
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [warn addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:warn animated:YES completion:nil];
        return;
    }
    [AISettings setStyleProfile:text forChat:_chatId];

    // 对方信息：只保存填了的字段
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSString *call = [_callField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (call.length > 0) info[@"call"] = call;
    NSString *rel = [_relationField.text stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (rel.length > 0) info[@"relation"] = rel;
    NSString *favor = @[@"高", @"中", @"低"][_favorControl.selectedSegmentIndex];
    info[@"favor"] = favor;
    NSString *basic = [_basicView.text stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (basic.length > 0) info[@"basic"] = basic;
    NSString *note = [_noteView.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (note.length > 0) info[@"note"] = note;
    [AISettings setFriendInfo:info forChat:_chatId];

    UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"已保存"
                                                                message:@"档案和对方信息已更新，之后与这位好友聊天会按它说话。"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ok addAction:[UIAlertAction actionWithTitle:@"知道了"
                                          style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *action) {
        [self dismissOrPop];
    }]];
    [self presentViewController:ok animated:YES completion:nil];
}

- (void)cancelTapped {
    [self dismissOrPop];
}

- (void)dismissOrPop {
    if (self.navigationController.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
