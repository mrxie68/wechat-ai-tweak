#import "AIPromptEditorViewController.h"
#import "AISettings.h"
#import "AIConfig.h"

@interface AIPromptEditorViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIView *switchCard;
@property (nonatomic, strong) UILabel *enabledLabel;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UIView *keyCard;
@property (nonatomic, strong) UILabel *keyLabel;
@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UIView *modelCard;
@property (nonatomic, strong) UILabel *modelLabel;
@property (nonatomic, strong) UILabel *modelValueLabel;
@property (nonatomic, strong) UIView *delayCard;
@property (nonatomic, strong) UILabel *delayLabel;
@property (nonatomic, strong) UITextField *delayField;
@property (nonatomic, strong) UIView *promptCard;
@property (nonatomic, strong) UILabel *promptLabel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *promptHint;
@property (nonatomic, strong) UIView *styleCard;
@property (nonatomic, strong) UILabel *styleLabel;
@property (nonatomic, strong) UITextView *styleView;
@property (nonatomic, strong) UILabel *styleHint;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) NSString *apiKeyReal;   // 当前真实 API Key（界面只显示掩码）
@property (nonatomic) BOOL editingKey;               // 用户正在编辑 Key（编辑时才显示明文）
@property (nonatomic) BOOL keyboardVisible;
@end

@implementation AIPromptEditorViewController

static UIView *makeCard(void) {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 12;
    card.layer.masksToBounds = YES;
    return card;
}

static UILabel *makeRowLabel(NSString *text) {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = [UIFont systemFontOfSize:16];
    label.textColor = [UIColor labelColor];
    return label;
}

static UITextField *makeRowField(NSString *placeholder) {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleNone;
    field.font = [UIFont systemFontOfSize:15];
    field.textAlignment = NSTextAlignmentRight;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    return field;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"AI 设置";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    // 模态弹出（AI 设置 命令）才显示“取消”；被 wcplugins 推入导航栈时用微信自带的返回
    BOOL isModal = (self.navigationController.presentingViewController != nil);
    if (isModal) {
        UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(cancelTapped)];
        self.navigationItem.leftBarButtonItem = cancel;
    }

    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithTitle:@"保存"
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = save;

    // 机器人开关
    self.switchCard = makeCard();
    [self.view addSubview:self.switchCard];
    self.enabledLabel = makeRowLabel(@"机器人开关");
    [self.switchCard addSubview:self.enabledLabel];
    self.enabledSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.enabledSwitch.on = [AISettings enabled];
    [self.switchCard addSubview:self.enabledSwitch];

    // API Key
    self.keyCard = makeCard();
    [self.view addSubview:self.keyCard];
    self.keyLabel = makeRowLabel(@"API Key");
    [self.keyCard addSubview:self.keyLabel];
    self.apiKeyField = makeRowField(@"sk- 开头");
    self.apiKeyField.delegate = self;
    self.apiKeyReal = [AISettings apiKey];
    self.editingKey = NO;
    self.apiKeyField.text = [self maskedKey:self.apiKeyReal];
    [self.keyCard addSubview:self.apiKeyField];

    // 模型
    self.modelCard = makeCard();
    [self.view addSubview:self.modelCard];
    self.modelLabel = makeRowLabel(@"模型名");
    [self.modelCard addSubview:self.modelLabel];
    self.modelValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.modelValueLabel.font = [UIFont systemFontOfSize:15];
    self.modelValueLabel.textColor = [UIColor secondaryLabelColor];
    self.modelValueLabel.textAlignment = NSTextAlignmentRight;
    [self refreshModelLabel];
    [self.modelCard addSubview:self.modelValueLabel];
    self.modelCard.userInteractionEnabled = YES;
    [self.modelCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                          initWithTarget:self action:@selector(modelTapped)]];

    // 思考延迟
    self.delayCard = makeCard();
    [self.view addSubview:self.delayCard];
    self.delayLabel = makeRowLabel(@"思考延迟");
    [self.delayCard addSubview:self.delayLabel];
    self.delayField = makeRowField(@"秒");
    self.delayField.keyboardType = UIKeyboardTypeDecimalPad;
    self.delayField.text = [NSString stringWithFormat:@"%.1f", [AISettings replyDelay]];
    [self.delayCard addSubview:self.delayField];

    // 系统提示词
    self.promptCard = makeCard();
    [self.view addSubview:self.promptCard];
    self.promptLabel = makeRowLabel(@"系统提示词");
    [self.promptCard addSubview:self.promptLabel];
    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.font = [UIFont systemFontOfSize:15];
    self.textView.text = [AISettings autoSystemPrompt];
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4);
    self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.promptCard addSubview:self.textView];
    self.promptHint = [[UILabel alloc] initWithFrame:CGRectZero];
    self.promptHint.text = @"自动回复时 AI 扮演你的要求";
    self.promptHint.font = [UIFont systemFontOfSize:12];
    self.promptHint.textColor = [UIColor secondaryLabelColor];
    [self.promptCard addSubview:self.promptHint];

    // 聊天风格样本：粘贴你自己的聊天记录，AI 会模仿你的语气习惯
    self.styleCard = makeCard();
    [self.view addSubview:self.styleCard];
    self.styleLabel = makeRowLabel(@"聊天风格样本");
    [self.styleCard addSubview:self.styleLabel];
    self.styleView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.styleView.font = [UIFont systemFontOfSize:15];
    self.styleView.text = [AISettings styleSamples];
    self.styleView.backgroundColor = [UIColor clearColor];
    self.styleView.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4);
    self.styleView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.styleCard addSubview:self.styleView];
    self.styleHint = [[UILabel alloc] initWithFrame:CGRectZero];
    self.styleHint.text = @"粘贴你自己的聊天记录片段，AI 会模仿这个语气和习惯；留空则用默认风格";
    self.styleHint.font = [UIFont systemFontOfSize:12];
    self.styleHint.textColor = [UIColor secondaryLabelColor];
    [self.styleCard addSubview:self.styleHint];

    // 恢复默认
    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"恢复默认" forState:UIControlStateNormal];
    [self.resetButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    self.resetButton.titleLabel.font = [UIFont systemFontOfSize:16];
    self.resetButton.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.resetButton.layer.cornerRadius = 12;
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resetButton];

    // 键盘处理：弹出时整体上移，避免挡住输入框
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    CGFloat topInset = self.view.safeAreaInsets.top;
    CGFloat bottomInset = self.view.safeAreaInsets.bottom;
    CGFloat margin = 16;
    CGFloat cardWidth = width - margin * 2;
    CGFloat rowHeight = 48;
    CGFloat gap = 8; // 行与行之间的小间隙
    CGFloat y = topInset + margin + 4;

    self.switchCard.frame = CGRectMake(margin, y, cardWidth, 56);
    y += 56 + 12;

    self.keyCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.modelCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.delayCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + 12;

    // 提示词和风格样本两个大卡片平分剩余空间
    CGFloat textArea = height - y - 48 - 12 - 12 - bottomInset;
    CGFloat textCardHeight = MAX(100, (textArea - 12) / 2);
    self.promptCard.frame = CGRectMake(margin, y, cardWidth, textCardHeight);
    y += textCardHeight + 12;
    self.styleCard.frame = CGRectMake(margin, y, cardWidth, textCardHeight);
    y += textCardHeight + 12;
    self.resetButton.frame = CGRectMake(margin, y, cardWidth, 48);

    // 卡片内部布局
    self.enabledLabel.frame = CGRectMake(16, 0, cardWidth - 90, 56);
    self.enabledSwitch.frame = CGRectMake(cardWidth - 60 - 14, 13, 60, 30);

    [self layoutLabel:self.keyLabel field:self.apiKeyField cardWidth:cardWidth];
    self.modelLabel.frame = CGRectMake(16, 0, 110, 48);
    self.modelValueLabel.frame = CGRectMake(130, 0, cardWidth - 130 - 26, 48);
    [self layoutLabel:self.delayLabel field:self.delayField cardWidth:cardWidth];

    self.promptLabel.frame = CGRectMake(16, 12, cardWidth - 32, 20);
    self.textView.frame = CGRectMake(12, 38, cardWidth - 24, textCardHeight - 38 - 26);
    self.promptHint.frame = CGRectMake(16, textCardHeight - 22, cardWidth - 32, 16);

    self.styleLabel.frame = CGRectMake(16, 12, cardWidth - 32, 20);
    self.styleView.frame = CGRectMake(12, 38, cardWidth - 24, textCardHeight - 38 - 26);
    self.styleHint.frame = CGRectMake(16, textCardHeight - 22, cardWidth - 32, 16);
}

- (void)layoutLabel:(UILabel *)label field:(UITextField *)field cardWidth:(CGFloat)cardWidth {
    label.frame = CGRectMake(16, 0, 110, 48);
    field.frame = CGRectMake(130, 0, cardWidth - 130 - 14, 48);
}

- (NSString *)maskedKey:(NSString *)key {
    if (key.length <= 8) return @"••••••••";
    return [NSString stringWithFormat:@"%@••••%@",
            [key substringToIndex:6],
            [key substringFromIndex:key.length - 4]];
}

- (void)refreshModelLabel {
    self.modelValueLabel.text = [NSString stringWithFormat:@"%@ ›", [AISettings model]];
}

- (void)modelTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择模型"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *models = @[@"deepseek-v4-flash", @"deepseek-v4-pro"];
    for (NSString *modelName in models) {
        [sheet addAction:[UIAlertAction actionWithTitle:modelName
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [AISettings setModel:modelName];
            [self refreshModelLabel];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"自定义…"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self promptCustomModel];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    // iPad 上 action sheet 需要锚点
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.modelCard;
        sheet.popoverPresentationController.sourceRect = self.modelCard.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptCustomModel {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"自定义模型"
                                                                   message:@"输入完整模型名（需你的 API 支持）"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [AISettings model];
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length > 0) {
            [AISettings setModel:name];
            [self refreshModelLabel];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    if (textField == self.apiKeyField && !self.editingKey) {
        self.editingKey = YES;
        if (self.apiKeyReal.length > 0) {
            textField.text = self.apiKeyReal;
        }
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.apiKeyField) {
        self.editingKey = NO;
        self.apiKeyReal = textField.text;
        textField.text = [self maskedKey:self.apiKeyReal];
    }
}

- (void)keyboardWillShow:(NSNotification *)note {
    CGRect kbFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat covered = kbFrame.size.height - (self.view.bounds.size.height - 240);
    if (covered > 0 && !self.keyboardVisible) {
        self.keyboardVisible = YES;
        [UIView animateWithDuration:0.25 animations:^{
            self.view.transform = CGAffineTransformMakeTranslation(0, -covered);
        }];
    }
}

- (void)keyboardWillHide:(NSNotification *)note {
    if (self.keyboardVisible) {
        self.keyboardVisible = NO;
        [UIView animateWithDuration:0.25 animations:^{
            self.view.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dismissOrPop {
    if (self.navigationController.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)cancelTapped {
    [self dismissOrPop];
}

- (void)saveTapped {
    NSString *key = self.editingKey ? self.apiKeyField.text : self.apiKeyReal;
    [AISettings setEnabled:self.enabledSwitch.on];
    [AISettings setApiKey:key];
    double delay = [self.delayField.text doubleValue];
    [AISettings setReplyDelay:(delay > 0 && delay <= 30) ? delay : kAIReplyDelaySeconds];
    [AISettings setAutoSystemPrompt:self.textView.text];
    [AISettings setStyleSamples:self.styleView.text];
    [self dismissOrPop];
}

- (void)resetTapped {
    self.enabledSwitch.on = YES;
    self.apiKeyReal = kAIAPIKey;
    self.apiKeyField.text = [self maskedKey:kAIAPIKey];
    self.editingKey = NO;
    [AISettings setModel:kAIModel];
    [self refreshModelLabel];
    self.delayField.text = [NSString stringWithFormat:@"%.1f", kAIReplyDelaySeconds];
    self.textView.text = kAIAutoSystemPrompt;
    self.styleView.text = @"";
}

@end
