#import "AIPromptEditorViewController.h"
#import "AISettings.h"
#import "AIConfig.h"

@interface AIPromptEditorViewController ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIButton *resetButton;
@end

@implementation AIPromptEditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"AI 提示词";
    self.view.backgroundColor = [UIColor whiteColor];

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(cancelTapped)];
    self.navigationItem.leftBarButtonItem = cancel;

    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithTitle:@"保存"
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = save;

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    self.textView.font = [UIFont systemFontOfSize:16];
    self.textView.text = [AISettings autoSystemPrompt];
    self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.textView];

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"恢复默认" forState:UIControlStateNormal];
    [self.resetButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resetButton];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    self.textView.frame = CGRectMake(12, 12, width - 24, height - 120);
    self.resetButton.frame = CGRectMake(12, height - 90, width - 24, 44);
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveTapped {
    [AISettings setAutoSystemPrompt:self.textView.text];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetTapped {
    self.textView.text = kAIAutoSystemPrompt;
}

@end
