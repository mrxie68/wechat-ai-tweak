#import "AIPromptEditorViewController.h"
#import "AISettings.h"
#import "AIConfig.h"
#import "AIContext.h"

// 状态字符串由 WeChatAIHandler 提供（同一个 dylib 内，无需头文件）
@interface WeChatAIHandler : NSObject
+ (NSString *)statusString;
@end

@interface AIPromptEditorViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *switchCard;
@property (nonatomic, strong) UILabel *enabledLabel;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *statusValueLabel;
@property (nonatomic, strong) UIView *singleChatCard;
@property (nonatomic, strong) UILabel *singleChatLabel;
@property (nonatomic, strong) UISwitch *singleChatSwitch;
@property (nonatomic, strong) UIView *groupChatCard;
@property (nonatomic, strong) UILabel *groupChatLabel;
@property (nonatomic, strong) UISwitch *groupChatSwitch;
@property (nonatomic, strong) UILabel *categoryHint;
@property (nonatomic, strong) UIView *modeCard;
@property (nonatomic, strong) UILabel *modeLabel;
@property (nonatomic, strong) UILabel *modeValueLabel;
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
@property (nonatomic, strong) UIView *memoryCard;
@property (nonatomic, strong) UILabel *memoryLabel;
@property (nonatomic, strong) UILabel *memoryValueLabel;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) NSString *apiKeyReal;   // 当前真实 API Key（界面只显示掩码）
@property (nonatomic) BOOL editingKey;               // 用户正在编辑 Key（编辑时才显示明文）
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

static UILabel *makeValueLabel(void) {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = [UIFont systemFontOfSize:15];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentRight;
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

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.scrollView addSubview:self.contentView];

    // 模态弹出才显示“取消”；被 wcplugins 推入导航栈时用微信自带的返回
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
    [self.contentView addSubview:self.switchCard];
    self.enabledLabel = makeRowLabel(@"机器人开关");
    [self.switchCard addSubview:self.enabledLabel];
    self.enabledSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.enabledSwitch.on = [AISettings enabled];
    [self.switchCard addSubview:self.enabledSwitch];

    // AI 状态（二级入口，点开弹窗展示运行状态）
    self.statusCard = makeCard();
    [self.contentView addSubview:self.statusCard];
    self.statusLabel = makeRowLabel(@"AI 状态");
    [self.statusCard addSubview:self.statusLabel];
    self.statusValueLabel = makeValueLabel();
    self.statusValueLabel.text = @"›";
    [self.statusCard addSubview:self.statusValueLabel];
    self.statusCard.userInteractionEnabled = YES;
    [self.statusCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                           initWithTarget:self action:@selector(statusTapped)]];

    // 单聊 AI 助手（一键开/关所有单聊）
    self.singleChatCard = makeCard();
    [self.contentView addSubview:self.singleChatCard];
    self.singleChatLabel = makeRowLabel(@"单聊 AI 助手");
    [self.singleChatCard addSubview:self.singleChatLabel];
    self.singleChatSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.singleChatSwitch.on = [AISettings singleChatEnabled];
    [self.singleChatCard addSubview:self.singleChatSwitch];

    // 群聊 AI 助手（一键开/关所有群聊）
    self.groupChatCard = makeCard();
    [self.contentView addSubview:self.groupChatCard];
    self.groupChatLabel = makeRowLabel(@"群聊 AI 助手");
    [self.groupChatCard addSubview:self.groupChatLabel];
    self.groupChatSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.groupChatSwitch.on = [AISettings groupChatEnabled];
    [self.groupChatCard addSubview:self.groupChatSwitch];

    // 类别开关说明：避免误解“关了还在回”
    self.categoryHint = [[UILabel alloc] initWithFrame:CGRectZero];
    self.categoryHint.text = @"提示：上面两个开关只改这一类会话的默认状态；在聊天信息页单独开/关过的会话不受影响。默认单聊、群聊都是关闭的；想一键全部停用，请关掉“机器人开关”。";
    self.categoryHint.font = [UIFont systemFontOfSize:12];
    self.categoryHint.textColor = [UIColor secondaryLabelColor];
    self.categoryHint.numberOfLines = 0;
    [self.contentView addSubview:self.categoryHint];

    // 回复模式
    self.modeCard = makeCard();
    [self.contentView addSubview:self.modeCard];
    self.modeLabel = makeRowLabel(@"回复模式");
    [self.modeCard addSubview:self.modeLabel];
    self.modeValueLabel = makeValueLabel();
    [self refreshModeLabel];
    [self.modeCard addSubview:self.modeValueLabel];
    self.modeCard.userInteractionEnabled = YES;
    [self.modeCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                         initWithTarget:self action:@selector(modeTapped)]];

    // API Key（掩码显示，编辑时才显示明文）
    self.keyCard = makeCard();
    [self.contentView addSubview:self.keyCard];
    self.keyLabel = makeRowLabel(@"API Key");
    [self.keyCard addSubview:self.keyLabel];
    self.apiKeyField = makeRowField(@"sk- 开头");
    self.apiKeyField.delegate = self;
    self.apiKeyReal = [AISettings apiKey];
    self.editingKey = NO;
    self.apiKeyField.text = [self maskedKey:self.apiKeyReal];
    [self.keyCard addSubview:self.apiKeyField];

    // 模型名（点一下选择）
    self.modelCard = makeCard();
    [self.contentView addSubview:self.modelCard];
    self.modelLabel = makeRowLabel(@"模型名");
    [self.modelCard addSubview:self.modelLabel];
    self.modelValueLabel = makeValueLabel();
    [self refreshModelLabel];
    [self.modelCard addSubview:self.modelValueLabel];
    self.modelCard.userInteractionEnabled = YES;
    [self.modelCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                          initWithTarget:self action:@selector(modelTapped)]];

    // 思考延迟
    self.delayCard = makeCard();
    [self.contentView addSubview:self.delayCard];
    self.delayLabel = makeRowLabel(@"思考延迟");
    [self.delayCard addSubview:self.delayLabel];
    self.delayField = makeRowField(@"秒");
    self.delayField.keyboardType = UIKeyboardTypeDecimalPad;
    self.delayField.text = [NSString stringWithFormat:@"%.1f", [AISettings replyDelay]];
    [self.delayCard addSubview:self.delayField];

    // 系统提示词
    self.promptCard = makeCard();
    [self.contentView addSubview:self.promptCard];
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

    // 聊天风格样本
    self.styleCard = makeCard();
    [self.contentView addSubview:self.styleCard];
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

    // 清空记忆（总开关：清掉所有会话的上下文）
    self.memoryCard = makeCard();
    [self.contentView addSubview:self.memoryCard];
    self.memoryLabel = makeRowLabel(@"清空记忆");
    self.memoryLabel.textColor = [UIColor systemRedColor];
    [self.memoryCard addSubview:self.memoryLabel];
    self.memoryValueLabel = makeValueLabel();
    self.memoryValueLabel.text = @"›";
    self.memoryValueLabel.textColor = [UIColor systemRedColor];
    [self.memoryCard addSubview:self.memoryValueLabel];
    self.memoryCard.userInteractionEnabled = YES;
    [self.memoryCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                           initWithTarget:self action:@selector(memoryTapped)]];

    // 恢复默认
    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"恢复默认" forState:UIControlStateNormal];
    [self.resetButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    self.resetButton.titleLabel.font = [UIFont systemFontOfSize:16];
    self.resetButton.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.resetButton.layer.cornerRadius = 12;
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.resetButton];

    // 键盘处理：调整滚动区底部 inset，避免挡住输入框
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

    self.scrollView.frame = self.view.bounds;

    CGFloat width = self.scrollView.bounds.size.width;
    CGFloat margin = 16;
    CGFloat cardWidth = width - margin * 2;
    CGFloat rowHeight = 48;
    CGFloat gap = 8;
    CGFloat y = 12;

    self.switchCard.frame = CGRectMake(margin, y, cardWidth, 56);
    y += 56 + 12;

    self.statusCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.singleChatCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.groupChatCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.categoryHint.frame = CGRectMake(margin + 4, y, cardWidth - 8, 52);
    y += 52 + 8;
    self.modeCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.keyCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.modelCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.delayCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + 12;

    CGFloat textCardHeight = 150;
    self.promptCard.frame = CGRectMake(margin, y, cardWidth, textCardHeight);
    y += textCardHeight + 12;
    self.styleCard.frame = CGRectMake(margin, y, cardWidth, textCardHeight);
    y += textCardHeight + 12;

    self.memoryCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + 12;
    self.resetButton.frame = CGRectMake(margin, y, cardWidth, 48);
    y += 48 + 24;

    self.contentView.frame = CGRectMake(0, 0, width, y);
    self.scrollView.contentSize = CGSizeMake(width, y);

    // 卡片内部布局
    self.enabledLabel.frame = CGRectMake(16, 0, cardWidth - 90, 56);
    self.enabledSwitch.frame = CGRectMake(cardWidth - 60 - 14, 13, 60, 30);

    self.statusLabel.frame = CGRectMake(16, 0, 200, rowHeight);
    self.statusValueLabel.frame = CGRectMake(cardWidth - 50, 0, 30, rowHeight);

    self.singleChatLabel.frame = CGRectMake(16, 0, 200, rowHeight);
    self.singleChatSwitch.frame = CGRectMake(cardWidth - 60 - 14, (rowHeight - 30) / 2, 60, 30);

    self.groupChatLabel.frame = CGRectMake(16, 0, 200, rowHeight);
    self.groupChatSwitch.frame = CGRectMake(cardWidth - 60 - 14, (rowHeight - 30) / 2, 60, 30);

    self.modeLabel.frame = CGRectMake(16, 0, 110, rowHeight);
    self.modeValueLabel.frame = CGRectMake(130, 0, cardWidth - 130 - 14, rowHeight);

    [self layoutLabel:self.keyLabel field:self.apiKeyField cardWidth:cardWidth];

    self.modelLabel.frame = CGRectMake(16, 0, 110, rowHeight);
    self.modelValueLabel.frame = CGRectMake(130, 0, cardWidth - 130 - 26, rowHeight);

    [self layoutLabel:self.delayLabel field:self.delayField cardWidth:cardWidth];

    self.promptLabel.frame = CGRectMake(16, 12, cardWidth - 32, 20);
    self.textView.frame = CGRectMake(12, 38, cardWidth - 24, textCardHeight - 38 - 26);
    self.promptHint.frame = CGRectMake(16, textCardHeight - 22, cardWidth - 32, 16);

    self.styleLabel.frame = CGRectMake(16, 12, cardWidth - 32, 20);
    self.styleView.frame = CGRectMake(12, 38, cardWidth - 24, textCardHeight - 38 - 26);
    self.styleHint.frame = CGRectMake(16, textCardHeight - 22, cardWidth - 32, 16);

    self.memoryLabel.frame = CGRectMake(16, 0, 200, rowHeight);
    self.memoryValueLabel.frame = CGRectMake(cardWidth - 50, 0, 30, rowHeight);
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

- (void)refreshModeLabel {
    self.modeValueLabel.text = [[AISettings replyMode] isEqualToString:@"auto"]
        ? @"自动代替聊天" : @"手动 @AI 触发";
}

- (void)statusTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"微信 AI 状态"
                                                                   message:[WeChatAIHandler statusString]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)modeTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"回复模式"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"自动代替聊天（推荐）"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [AISettings setReplyMode:@"auto"];
        [self refreshModeLabel];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"手动触发（@AI 开头才回）"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [AISettings setReplyMode:@"trigger"];
        [self refreshModeLabel];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.modeCard;
        sheet.popoverPresentationController.sourceRect = self.modeCard.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)memoryTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空全部记忆"
                                                                   message:@"将清空所有会话的聊天上下文，AI 会忘记之前的对话，且无法恢复。确定清空？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [[AIContext shared] clearAll];
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"已清空"
                                                                      message:@"全部会话的记忆已清空，AI 从现在开始重新了解上下文。"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:done animated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
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
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = kbFrame.size.height;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
}

- (void)keyboardWillHide:(NSNotification *)note {
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = 0;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
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
    [AISettings setSingleChatEnabled:self.singleChatSwitch.on];
    [AISettings setGroupChatEnabled:self.groupChatSwitch.on];
    [AISettings setApiKey:key];
    double delay = [self.delayField.text doubleValue];
    [AISettings setReplyDelay:(delay > 0 && delay <= 30) ? delay : kAIReplyDelaySeconds];
    [AISettings setAutoSystemPrompt:self.textView.text];
    [AISettings setStyleSamples:self.styleView.text];
    [self dismissOrPop];
}

- (void)resetTapped {
    self.enabledSwitch.on = YES;
    self.singleChatSwitch.on = NO;
    self.groupChatSwitch.on = NO;
    self.apiKeyReal = kAIAPIKey;
    self.apiKeyField.text = [self maskedKey:kAIAPIKey];
    self.editingKey = NO;
    [AISettings setModel:kAIModel];
    [self refreshModelLabel];
    [AISettings setReplyMode:kAIReplyMode];
    [self refreshModeLabel];
    self.delayField.text = [NSString stringWithFormat:@"%.1f", kAIReplyDelaySeconds];
    self.textView.text = kAIAutoSystemPrompt;
    self.styleView.text = @"";
}

@end
