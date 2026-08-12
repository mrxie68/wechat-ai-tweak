#import "AIPromptEditorViewController.h"
#import "AISettings.h"
#import "AIConfig.h"

@interface AIPromptEditorViewController ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UITextField *modelField;
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

    self.apiKeyField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    self.apiKeyField.placeholder = @"API Key（sk- 开头）";
    self.apiKeyField.text = [AISettings apiKey];
    self.apiKeyField.borderStyle = UITextBorderStyleRoundedRect;
    self.apiKeyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.apiKeyField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.apiKeyField.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.apiKeyField];

    self.modelField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    self.modelField.placeholder = @"模型名（如 deepseek-chat）";
    self.modelField.text = [AISettings model];
    self.modelField.borderStyle = UITextBorderStyleRoundedRect;
    self.modelField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.modelField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.modelField.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.modelField];

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
    self.apiKeyField.frame = CGRectMake(12, 12, width - 24, 40);
    self.modelField.frame = CGRectMake(12, 60, width - 24, 40);
    self.textView.frame = CGRectMake(12, 108, width - 24, height - 108 - 90);
    self.resetButton.frame = CGRectMake(12, height - 90, width - 24, 44);
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveTapped {
    [AISettings setApiKey:self.apiKeyField.text];
    [AISettings setModel:self.modelField.text];
    [AISettings setAutoSystemPrompt:self.textView.text];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetTapped {
    self.apiKeyField.text = kAIAPIKey;
    self.modelField.text = kAIModel;
    self.textView.text = kAIAutoSystemPrompt;
}

@end
