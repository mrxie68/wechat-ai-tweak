#import "AIProfileEditorViewController.h"
#import "AISettings.h"

@implementation AIProfileEditorViewController {
    NSString *_chatId;
    NSString *_initialProfile;
    UITextView *_textView;
}

- (instancetype)initWithChatId:(NSString *)chatId profile:(NSString *)profile {
    self = [super init];
    if (self) {
        _chatId = [chatId copy];
        _initialProfile = [profile copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"编辑风格档案";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(saveTapped)];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, self.view.bounds.size.width - 32, 18)];
    hint.text = @"AI 与这位好友聊天时会按这份档案说话，可直接修改完善。";
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = [UIColor secondaryLabelColor];
    [self.view addSubview:hint];

    _textView = [[UITextView alloc] initWithFrame:
                 CGRectMake(12, 38, self.view.bounds.size.width - 24, self.view.bounds.size.height - 50)];
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
    UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"已保存"
                                                                message:@"风格档案已更新，之后与这位好友聊天会按它说话。"
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
