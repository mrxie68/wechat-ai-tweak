#import "AIProfileEditorViewController.h"
#import "AISettings.h"

@implementation AIProfileEditorViewController {
    NSString *_chatId;
    NSString *_initialProfile;
    NSDictionary *_friendInfo;
    UILabel *_callLabel;
    UILabel *_relLabel;
    UILabel *_favLabel;
    UILabel *_basicLabel;
    UILabel *_noteLabel;
    UILabel *_profileLabel;
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

- (UILabel *)makeFieldLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = [UIFont systemFontOfSize:15];
    return label;
}

- (UILabel *)makeHintLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = [UIFont systemFontOfSize:12];
    label.textColor = [UIColor secondaryLabelColor];
    return label;
}

- (UITextView *)makeSmallTextView {
    UITextView *view = [[UITextView alloc] initWithFrame:CGRectZero];
    view.font = [UIFont systemFontOfSize:14];
    view.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    view.layer.cornerRadius = 8;
    return view;
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
    _callLabel = [self makeFieldLabel:@"称呼"];
    [self.view addSubview:_callLabel];
    _callField = [[UITextField alloc] initWithFrame:CGRectZero];
    _callField.placeholder = @"如：老张 / 老铁 / 阿凯";
    _callField.font = [UIFont systemFontOfSize:15];
    _callField.borderStyle = UITextBorderStyleRoundedRect;
    _callField.text = _friendInfo[@"call"] ?: @"";
    [self.view addSubview:_callField];

    _relLabel = [self makeFieldLabel:@"关系"];
    [self.view addSubview:_relLabel];
    _relationField = [[UITextField alloc] initWithFrame:CGRectZero];
    _relationField.placeholder = @"如：好朋友 / 同事 / 家人";
    _relationField.font = [UIFont systemFontOfSize:15];
    _relationField.borderStyle = UITextBorderStyleRoundedRect;
    _relationField.text = _friendInfo[@"relation"] ?: @"";
    [self.view addSubview:_relationField];

    _favLabel = [self makeFieldLabel:@"好感度"];
    [self.view addSubview:_favLabel];
    _favorControl = [[UISegmentedControl alloc] initWithItems:@[@"高", @"中", @"低"]];
    _favorControl.frame = CGRectZero;
    NSString *fav = _friendInfo[@"favor"] ?: @"中";
    _favorControl.selectedSegmentIndex = [fav isEqualToString:@"高"] ? 0 : ([fav isEqualToString:@"低"] ? 2 : 1);
    [self.view addSubview:_favorControl];

    _basicLabel = [self makeHintLabel:@"对方基本情况（工作/家庭/住址，AI 以此为准不编造）"];
    [self.view addSubview:_basicLabel];
    _basicView = [self makeSmallTextView];
    _basicView.text = _friendInfo[@"basic"] ?: @"";
    [self.view addSubview:_basicView];

    _noteLabel = [self makeHintLabel:@"备注（性格/习惯/共同经历/雷区）"];
    [self.view addSubview:_noteLabel];
    _noteView = [self makeSmallTextView];
    _noteView.text = _friendInfo[@"note"] ?: @"";
    [self.view addSubview:_noteView];

    _profileLabel = [self makeHintLabel:@"风格档案（AI 学出来的，可修改完善）"];
    [self.view addSubview:_profileLabel];
    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.font = [UIFont systemFontOfSize:15];
    _textView.text = _initialProfile;
    _textView.textContainerInset = UIEdgeInsetsMake(12, 8, 12, 8);
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _textView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    _textView.layer.cornerRadius = 12;
    [self.view addSubview:_textView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat top = self.view.safeAreaInsets.top + 12; // 避开导航栏，不再和取消/保存重叠
    CGFloat bottom = self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 16;
    CGFloat labelW = 56;
    CGFloat fieldX = 78;
    CGFloat fieldW = w - fieldX - 16;
    CGFloat rowH = 30;
    CGFloat gap = 8;
    CGFloat y = top;

    _callLabel.frame = CGRectMake(16, y, labelW, rowH);
    _callField.frame = CGRectMake(fieldX, y, fieldW, rowH);
    y += rowH + gap;

    _relLabel.frame = CGRectMake(16, y, labelW, rowH);
    _relationField.frame = CGRectMake(fieldX, y, fieldW, rowH);
    y += rowH + gap;

    _favLabel.frame = CGRectMake(16, y, labelW, rowH);
    _favorControl.frame = CGRectMake(fieldX, y, fieldW, rowH);
    y += rowH + gap;

    _basicLabel.frame = CGRectMake(16, y, w - 32, 16);
    y += 16 + 4;
    _basicView.frame = CGRectMake(16, y, w - 32, 52);
    y += 52 + 12;

    _noteLabel.frame = CGRectMake(16, y, w - 32, 16);
    y += 16 + 4;
    _noteView.frame = CGRectMake(16, y, w - 32, 52);
    y += 52 + 12;

    _profileLabel.frame = CGRectMake(16, y, w - 32, 16);
    y += 16 + 8;
    _textView.frame = CGRectMake(16, y, w - 32, MAX(bottom - y, 80));
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
