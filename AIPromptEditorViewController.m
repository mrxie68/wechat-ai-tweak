#import "AIPromptEditorViewController.h"
#import "AISettings.h"
#import "AIConfig.h"
#import "AIContext.h"
#import "AIAPIClient.h"
#import "AIProfileListViewController.h"

// 状态字符串由 WeChatAIHandler 提供（同一个 dylib 内，无需头文件）
@interface WeChatAIHandler : NSObject
+ (NSString *)statusString;
+(NSString *)selfUsrName;
+(BOOL)isActivatedForCurrentAccount;
@end

@interface AIPromptEditorViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *switchCard;
@property (nonatomic, strong) UILabel *enabledLabel;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UIView *activationCard;
@property (nonatomic, strong) UILabel *activationLabel;
@property (nonatomic, strong) UILabel *activationValueLabel;
@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *statusValueLabel;
@property (nonatomic, strong) UIView *profileListCard;
@property (nonatomic, strong) UILabel *profileListLabel;
@property (nonatomic, strong) UILabel *profileListValueLabel;
@property (nonatomic, strong) UIView *modeCard;
@property (nonatomic, strong) UILabel *modeLabel;
@property (nonatomic, strong) UILabel *modeValueLabel;
@property (nonatomic, strong) UIView *behaviorCard;
@property (nonatomic, strong) UILabel *groupLabel;
@property (nonatomic, strong) UISwitch *groupSwitch;
@property (nonatomic, strong) UILabel *stickerLabel;
@property (nonatomic, strong) UISwitch *stickerSwitch;
@property (nonatomic, strong) UIView *keyCard;
@property (nonatomic, strong) UILabel *keyLabel;
@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UIView *modelCard;
@property (nonatomic, strong) UILabel *modelLabel;
@property (nonatomic, strong) UILabel *modelValueLabel;
@property (nonatomic, strong) UIView *delayCard;
@property (nonatomic, strong) UILabel *delayLabel;
@property (nonatomic, strong) UITextField *delayField;
@property (nonatomic, strong) UIView *paramCard;
@property (nonatomic, strong) UILabel *tempLabel;
@property (nonatomic, strong) UITextField *tempField;
@property (nonatomic, strong) UILabel *freqLabel;
@property (nonatomic, strong) UITextField *freqField;
@property (nonatomic, strong) UILabel *presLabel;
@property (nonatomic, strong) UITextField *presField;
@property (nonatomic, strong) UILabel *typingLabel;
@property (nonatomic, strong) UISwitch *typingSwitch;
@property (nonatomic, strong) UIView *promptCard;
@property (nonatomic, strong) UILabel *promptLabel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *promptHint;
@property (nonatomic, strong) UIButton *promptResetButton;
@property (nonatomic, strong) UIView *styleCard;
@property (nonatomic, strong) UILabel *styleLabel;
@property (nonatomic, strong) UITextView *styleView;
@property (nonatomic, strong) UILabel *styleHint;
@property (nonatomic, strong) UIButton *styleResetButton;
@property (nonatomic, strong) UIView *profileCard;
@property (nonatomic, strong) UILabel *profileLabel;
@property (nonatomic, strong) UITextView *profileView;
@property (nonatomic, strong) UILabel *profileHint;
@property (nonatomic, strong) UIButton *profileResetButton;
@property (nonatomic, strong) UIView *memoryCard;
@property (nonatomic, strong) UILabel *memoryLabel;
@property (nonatomic, strong) UILabel *memoryValueLabel;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) NSString *apiKeyReal;   // 当前真实 API Key（界面只显示掩码）
@property (nonatomic) BOOL editingKey;               // 用户正在编辑 Key（编辑时才显示明文）
@property (nonatomic, strong) NSString *pendingModel; // 页面里选中的模型（保存时才落盘）
@property (nonatomic, strong) NSString *pendingMode;  // 页面里选中的回复模式（保存时才落盘）
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

    // 激活密钥（按微信账号区分：换号自动失效，防止多账号数据串用）
    self.activationCard = makeCard();
    [self.contentView addSubview:self.activationCard];
    self.activationLabel = makeRowLabel(@"激活密钥");
    [self.activationCard addSubview:self.activationLabel];
    self.activationValueLabel = makeValueLabel();
    [self.activationCard addSubview:self.activationValueLabel];
    self.activationCard.userInteractionEnabled = YES;
    [self.activationCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                               initWithTarget:self action:@selector(activationTapped)]];
    [self refreshActivationLabel];

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

    // 学习档案（二级入口：查看/删除已学习的好友档案）
    self.profileListCard = makeCard();
    [self.contentView addSubview:self.profileListCard];
    self.profileListLabel = makeRowLabel(@"学习档案");
    [self.profileListCard addSubview:self.profileListLabel];
    self.profileListValueLabel = makeValueLabel();
    self.profileListValueLabel.text = [NSString stringWithFormat:@"%ld ›",
                                       (long)[AISettings styleProfileCount]];
    [self.profileListCard addSubview:self.profileListValueLabel];
    self.profileListCard.userInteractionEnabled = YES;
    [self.profileListCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                                initWithTarget:self action:@selector(profileListTapped)]];

    // 回复模式
    self.modeCard = makeCard();
    [self.contentView addSubview:self.modeCard];
    self.modeLabel = makeRowLabel(@"回复模式");
    [self.modeCard addSubview:self.modeLabel];
    self.modeValueLabel = makeValueLabel();
    self.pendingMode = [AISettings replyMode];
    [self refreshModeLabel];
    [self.modeCard addSubview:self.modeValueLabel];
    self.modeCard.userInteractionEnabled = YES;
    [self.modeCard addGestureRecognizer:[[UITapGestureRecognizer alloc]
                                         initWithTarget:self action:@selector(modeTapped)]];

    // 回复行为：群聊只回提问 + 表情包轻回复
    self.behaviorCard = makeCard();
    [self.contentView addSubview:self.behaviorCard];
    self.groupLabel = makeRowLabel(@"群聊只回提问");
    [self.behaviorCard addSubview:self.groupLabel];
    self.groupSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.groupSwitch.on = [AISettings groupQuestionOnly];
    [self.behaviorCard addSubview:self.groupSwitch];
    self.stickerLabel = makeRowLabel(@"表情包轻回复");
    [self.behaviorCard addSubview:self.stickerLabel];
    self.stickerSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.stickerSwitch.on = [AISettings stickerLightReply];
    [self.behaviorCard addSubview:self.stickerSwitch];

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
    self.pendingModel = [AISettings model];
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

    // 高级参数（温度 / 频率惩罚 / 存在惩罚）
    self.paramCard = makeCard();
    [self.contentView addSubview:self.paramCard];
    self.tempLabel = makeRowLabel(@"温度");
    [self.paramCard addSubview:self.tempLabel];
    self.tempField = makeRowField(@"0~2");
    self.tempField.keyboardType = UIKeyboardTypeDecimalPad;
    self.tempField.text = [NSString stringWithFormat:@"%.2f", [AISettings temperature]];
    [self.paramCard addSubview:self.tempField];
    self.freqLabel = makeRowLabel(@"频率惩罚");
    [self.paramCard addSubview:self.freqLabel];
    self.freqField = makeRowField(@"0~2");
    self.freqField.keyboardType = UIKeyboardTypeDecimalPad;
    self.freqField.text = [NSString stringWithFormat:@"%.2f", [AISettings frequencyPenalty]];
    [self.paramCard addSubview:self.freqField];
    self.presLabel = makeRowLabel(@"存在惩罚");
    [self.paramCard addSubview:self.presLabel];
    self.presField = makeRowField(@"0~2");
    self.presField.keyboardType = UIKeyboardTypeDecimalPad;
    self.presField.text = [NSString stringWithFormat:@"%.2f", [AISettings presencePenalty]];
    [self.paramCard addSubview:self.presField];
    self.typingLabel = makeRowLabel(@"模拟打字");
    [self.paramCard addSubview:self.typingLabel];
    self.typingSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.typingSwitch.on = [AISettings typingSimulation];
    [self.paramCard addSubview:self.typingSwitch];

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
    self.promptResetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.promptResetButton setTitle:@"恢复默认" forState:UIControlStateNormal];
    self.promptResetButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.promptResetButton addTarget:self action:@selector(resetPromptTapped)
                     forControlEvents:UIControlEventTouchUpInside];
    [self.promptCard addSubview:self.promptResetButton];

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
    self.styleHint.text = @"格式：Q:（对方说）/ A:（我说）交替，每行一条；AI 会作为真实对话范例学习。留空则用默认样本";
    self.styleHint.font = [UIFont systemFontOfSize:12];
    self.styleHint.textColor = [UIColor secondaryLabelColor];
    [self.styleCard addSubview:self.styleHint];
    self.styleResetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.styleResetButton setTitle:@"恢复默认" forState:UIControlStateNormal];
    self.styleResetButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.styleResetButton addTarget:self action:@selector(resetStyleTapped)
                    forControlEvents:UIControlEventTouchUpInside];
    [self.styleCard addSubview:self.styleResetButton];

    // 基础信息（AI 聊天时以此为准，没写的绝不编造）
    self.profileCard = makeCard();
    [self.contentView addSubview:self.profileCard];
    self.profileLabel = makeRowLabel(@"基础信息");
    [self.profileCard addSubview:self.profileLabel];
    self.profileView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.profileView.font = [UIFont systemFontOfSize:15];
    self.profileView.text = [AISettings userProfile];
    self.profileView.backgroundColor = [UIColor clearColor];
    self.profileView.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4);
    self.profileView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.profileCard addSubview:self.profileView];
    self.profileHint = [[UILabel alloc] initWithFrame:CGRectZero];
    self.profileHint.text = @"填你的真实信息，越具体越有生活感：称呼、工作、最近在折腾什么（比如做图/养花/写代码）、爱吃/不吃啥、常去的地方等。AI 只以此为准，没写的绝不编造。";
    self.profileHint.font = [UIFont systemFontOfSize:12];
    self.profileHint.textColor = [UIColor secondaryLabelColor];
    [self.profileCard addSubview:self.profileHint];
    self.profileResetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.profileResetButton setTitle:@"恢复默认" forState:UIControlStateNormal];
    self.profileResetButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.profileResetButton addTarget:self action:@selector(resetProfileTapped)
                      forControlEvents:UIControlEventTouchUpInside];
    [self.profileCard addSubview:self.profileResetButton];

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

    self.activationCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.statusCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.profileListCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.modeCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.behaviorCard.frame = CGRectMake(margin, y, cardWidth, rowHeight * 2);
    y += rowHeight * 2 + gap;
    self.keyCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.modelCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + gap;
    self.delayCard.frame = CGRectMake(margin, y, cardWidth, rowHeight);
    y += rowHeight + 12;
    self.paramCard.frame = CGRectMake(margin, y, cardWidth, rowHeight * 4);
    y += rowHeight * 4 + 12;

    CGFloat textCardHeight = 150;
    self.promptCard.frame = CGRectMake(margin, y, cardWidth, textCardHeight);
    y += textCardHeight + 12;
    self.styleCard.frame = CGRectMake(margin, y, cardWidth, textCardHeight);
    y += textCardHeight + 12;
    self.profileCard.frame = CGRectMake(margin, y, cardWidth, textCardHeight);
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

    self.activationLabel.frame = CGRectMake(16, 0, 200, rowHeight);
    self.activationValueLabel.frame = CGRectMake(cardWidth - 90, 0, 70, rowHeight);

    self.statusLabel.frame = CGRectMake(16, 0, 200, rowHeight);
    self.statusValueLabel.frame = CGRectMake(cardWidth - 50, 0, 30, rowHeight);

    self.profileListLabel.frame = CGRectMake(16, 0, 200, rowHeight);
    self.profileListValueLabel.frame = CGRectMake(cardWidth - 50, 0, 30, rowHeight);

    self.modeLabel.frame = CGRectMake(16, 0, 110, rowHeight);
    self.modeValueLabel.frame = CGRectMake(130, 0, cardWidth - 130 - 14, rowHeight);

    self.groupLabel.frame = CGRectMake(16, 0, 200, rowHeight);
    self.groupSwitch.frame = CGRectMake(cardWidth - 60 - 14, 9, 60, 30);
    self.stickerLabel.frame = CGRectMake(16, rowHeight, 200, rowHeight);
    self.stickerSwitch.frame = CGRectMake(cardWidth - 60 - 14, rowHeight + 9, 60, 30);

    [self layoutLabel:self.keyLabel field:self.apiKeyField cardWidth:cardWidth];

    self.modelLabel.frame = CGRectMake(16, 0, 110, rowHeight);
    self.modelValueLabel.frame = CGRectMake(130, 0, cardWidth - 130 - 26, rowHeight);

    [self layoutLabel:self.delayLabel field:self.delayField cardWidth:cardWidth];

    self.tempLabel.frame = CGRectMake(16, 0, 110, rowHeight);
    self.tempField.frame = CGRectMake(130, 0, cardWidth - 130 - 14, rowHeight);
    self.freqLabel.frame = CGRectMake(16, rowHeight, 110, rowHeight);
    self.freqField.frame = CGRectMake(130, rowHeight, cardWidth - 130 - 14, rowHeight);
    self.presLabel.frame = CGRectMake(16, rowHeight * 2, 110, rowHeight);
    self.presField.frame = CGRectMake(130, rowHeight * 2, cardWidth - 130 - 14, rowHeight);
    self.typingLabel.frame = CGRectMake(16, rowHeight * 3, 140, rowHeight);
    self.typingSwitch.frame = CGRectMake(cardWidth - 60 - 14, rowHeight * 3 + 9, 60, 30);

    self.promptLabel.frame = CGRectMake(16, 12, cardWidth - 110, 20);
    self.textView.frame = CGRectMake(12, 38, cardWidth - 24, textCardHeight - 38 - 26);
    self.promptHint.frame = CGRectMake(16, textCardHeight - 22, cardWidth - 32, 16);
    self.promptResetButton.frame = CGRectMake(cardWidth - 92, 6, 76, 26);

    self.styleLabel.frame = CGRectMake(16, 12, cardWidth - 110, 20);
    self.styleView.frame = CGRectMake(12, 38, cardWidth - 24, textCardHeight - 38 - 26);
    self.styleHint.frame = CGRectMake(16, textCardHeight - 22, cardWidth - 32, 16);
    self.styleResetButton.frame = CGRectMake(cardWidth - 92, 6, 76, 26);

    self.profileLabel.frame = CGRectMake(16, 12, cardWidth - 110, 20);
    self.profileView.frame = CGRectMake(12, 38, cardWidth - 24, textCardHeight - 38 - 26);
    self.profileHint.frame = CGRectMake(16, textCardHeight - 22, cardWidth - 32, 16);
    self.profileResetButton.frame = CGRectMake(cardWidth - 92, 6, 76, 26);

    self.memoryLabel.frame = CGRectMake(16, 0, 200, rowHeight);
    self.memoryValueLabel.frame = CGRectMake(cardWidth - 50, 0, 30, rowHeight);
}

- (void)layoutLabel:(UILabel *)label field:(UITextField *)field cardWidth:(CGFloat)cardWidth {
    label.frame = CGRectMake(16, 0, 110, 48);
    field.frame = CGRectMake(130, 0, cardWidth - 130 - 14, 48);
}

- (NSString *)maskedKey:(NSString *)key {
    if (key.length == 0) return @"";  // 未配置时显示占位符，而不是一串黑点
    if (key.length <= 8) return @"••••••••";
    return [NSString stringWithFormat:@"%@••••%@",
            [key substringToIndex:6],
            [key substringFromIndex:key.length - 4]];
}

- (void)refreshModelLabel {
    self.modelValueLabel.text = [NSString stringWithFormat:@"%@ ›", self.pendingModel];
}

- (void)refreshModeLabel {
    self.modeValueLabel.text = [self.pendingMode isEqualToString:@"auto"]
        ? @"自动代替聊天" : @"手动 @AI 触发";
}

- (void)statusTapped {
    NSString *statusText = [WeChatAIHandler statusString];
    // 完整内容自动复制到剪贴板，弹窗太长被截断时也能直接粘贴发出来
    [[UIPasteboard generalPasteboard] setString:statusText];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"微信 AI 状态"
                                                                   message:[statusText stringByAppendingString:@"\n\n（完整内容已复制到剪贴板，直接粘贴发我）"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"测试对话"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [self runTestConversation];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// AI 状态里的“测试对话”：走真实的 DeepSeek 请求，验证 Key/模型/参数/Few-Shot/网络全链路
- (void)runTestConversation {
    if (![WeChatAIHandler isActivatedForCurrentAccount]) {
        UIAlertController *warn = [UIAlertController alertControllerWithTitle:@"当前账号未激活"
                                                                     message:@"请先在设置页输入激活密钥，激活后才能测试对话。"
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [warn addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:warn animated:YES completion:nil];
        return;
    }
    if ([AISettings apiKey].length == 0) {
        UIAlertController *warn = [UIAlertController alertControllerWithTitle:@"未配置 API Key"
                                                                     message:@"请先在设置页的 API Key 一栏填入 DeepSeek Key 再测试。"
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [warn addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:warn animated:YES completion:nil];
        return;
    }

    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在测试对话"
                                                                     message:@"正在连接 DeepSeek 验证配置…"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
                                        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [progress.view addSubview:spinner];
    NSDictionary *views = @{@"spinner": spinner};
    [progress.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[spinner]-16-|"
                                                                         options:0 metrics:nil views:views]];
    [progress.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[spinner]-12-|"
                                                                         options:0 metrics:nil views:views]];
    [self presentViewController:progress animated:NO completion:nil];

    NSArray *history = @[@{@"role": @"user", @"content": @"在吗？测试一下，简单回一句就行。"}];
    [[AIAPIClient shared] sendMessages:history
                          systemPrompt:[AISettings autoSystemPrompt]
                          styleProfile:nil
                          userProfile:[AISettings userProfile]
                          fewShotEnabled:YES
                            completion:^(NSString *reply, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progress dismissViewControllerAnimated:NO completion:^{
                if (error) {
                    NSString *desc = error.localizedDescription ?: @"未知错误";
                    NSString *hint = @"";
                    if ([desc containsString:@"401"]) {
                        hint = @"\n\n大概率是 API Key 无效，去 DeepSeek 后台检查。";
                    } else if ([desc containsString:@"402"] || [desc containsString:@"余额"] ||
                               [desc containsString:@"insufficient"]) {
                        hint = @"\n\n大概率是余额不足。";
                    } else if ([desc containsString:@"timeout"] || [desc containsString:@"Timed out"]) {
                        hint = @"\n\n网络超时，检查网络后重试。";
                    }
                    UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"❌ 测试失败"
                                                                                 message:[NSString stringWithFormat:@"原因：%@%@", desc, hint]
                                                                          preferredStyle:UIAlertControllerStyleAlert];
                    [fail addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:fail animated:YES completion:nil];
                    return;
                }

                NSUInteger fsCount = [AIAPIClient fewShotMessageCount];
                NSString *fsDesc = fsCount > 0
                    ? [NSString stringWithFormat:@"%lu 条（%lu 组）",
                       (unsigned long)fsCount, (unsigned long)fsCount / 2]
                    : @"0 条（旧格式纯文本兜底）";
                NSString *okMsg = [NSString stringWithFormat:
                    @"AI 回复：%@\n\n参数检查：\n模型 %@\n温度 %.2f / 频率惩罚 %.2f / 存在惩罚 %.2f\n思考延迟 %.1f 秒 / 模拟打字 %@\nFew-Shot 样本：%@\nAPI Key：%@",
                    reply,
                    [AISettings model],
                    [AISettings temperature], [AISettings frequencyPenalty], [AISettings presencePenalty],
                    [AISettings replyDelay], [AISettings typingSimulation] ? @"开" : @"关",
                    fsDesc, [self maskedKey:[AISettings apiKey]]];
                UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"✅ 测试成功"
                                                                           message:okMsg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [ok addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:ok animated:YES completion:nil];
            }];
        });
    }];
}

- (void)modeTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"回复模式"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"自动代替聊天（推荐）"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        self.pendingMode = @"auto";
        [self refreshModeLabel];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"手动触发（@AI 开头才回）"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        self.pendingMode = @"trigger";
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
                                                                   message:@"将清空所有会话的聊天上下文和已学习的风格档案，AI 会忘记之前的对话，且无法恢复。确定清空？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [[AIContext shared] clearAll];
        [AISettings clearAllStyleProfiles];
        UIAlertController *done = [UIAlertController alertControllerWithTitle:@"已清空"
                                                                      message:@"全部会话的记忆和风格档案已清空，AI 从现在开始重新了解上下文。"
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
            self.pendingModel = modelName;
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
            self.pendingModel = name;
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
    [AISettings setApiKey:key];
    [AISettings setModel:self.pendingModel];
    [AISettings setReplyMode:self.pendingMode];
    double delay = [self.delayField.text doubleValue];
    [AISettings setReplyDelay:(delay > 0 && delay <= 30) ? delay : kAIReplyDelaySeconds];
    double temp = [self.tempField.text doubleValue];
    [AISettings setTemperature:(temp >= 0 && temp <= 2) ? temp : kAIRequestTemperature];
    double freq = [self.freqField.text doubleValue];
    [AISettings setFrequencyPenalty:(freq >= 0 && freq <= 2) ? freq : kAIRequestFrequencyPenalty];
    double pres = [self.presField.text doubleValue];
    [AISettings setPresencePenalty:(pres >= 0 && pres <= 2) ? pres : kAIRequestPresencePenalty];
    [AISettings setTypingSimulation:self.typingSwitch.on];
    [AISettings setGroupQuestionOnly:self.groupSwitch.on];
    [AISettings setStickerLightReply:self.stickerSwitch.on];
    [AISettings setAutoSystemPrompt:self.textView.text];
    [AISettings setStyleSamples:self.styleView.text];
    [AISettings setUserProfile:self.profileView.text];
    [self dismissOrPop];
}

- (void)resetTapped {
    self.enabledSwitch.on = YES;
    self.apiKeyReal = kAIAPIKey;
    self.apiKeyField.text = [self maskedKey:kAIAPIKey];
    self.editingKey = NO;
    self.pendingModel = kAIModel;
    [self refreshModelLabel];
    self.pendingMode = kAIReplyMode;
    [self refreshModeLabel];
    self.delayField.text = [NSString stringWithFormat:@"%.1f", kAIReplyDelaySeconds];
    self.tempField.text = [NSString stringWithFormat:@"%.2f", kAIRequestTemperature];
    self.freqField.text = [NSString stringWithFormat:@"%.2f", kAIRequestFrequencyPenalty];
    self.presField.text = [NSString stringWithFormat:@"%.2f", kAIRequestPresencePenalty];
    self.typingSwitch.on = YES;
    self.groupSwitch.on = YES;
    self.stickerSwitch.on = NO;
    self.textView.text = kAIAutoSystemPrompt;
    self.styleView.text = kAIStyleSamplesDefault;
    self.profileView.text = kAIUserProfile;
}

- (void)resetPromptTapped {
    self.textView.text = kAIAutoSystemPrompt;
}

- (void)resetStyleTapped {
    self.styleView.text = kAIStyleSamplesDefault;
}

- (void)resetProfileTapped {
    self.profileView.text = kAIUserProfile;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.profileListValueLabel.text = [NSString stringWithFormat:@"%ld ›",
                                       (long)[AISettings styleProfileCount]];
    [self refreshActivationLabel];
}

- (void)refreshActivationLabel {
    self.activationValueLabel.text = [WeChatAIHandler isActivatedForCurrentAccount]
        ? @"已激活 ›" : @"未激活 ›";
}

- (void)activationTapped {
    NSString *usr = [WeChatAIHandler selfUsrName];
    BOOL activated = [WeChatAIHandler isActivatedForCurrentAccount];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"激活密钥"
                                                                  message:activated
        ? [NSString stringWithFormat:@"当前微信账号（%@）已激活。可以修改密钥，或停用本账号。", usr]
        : [NSString stringWithFormat:@"当前微信账号（%@）未激活。\n输入一个密钥即可激活本账号（仅本机使用，不做远程验证）。", usr]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"输入密钥";
        tf.secureTextEntry = YES;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:activated ? @"修改密钥" : @"激活"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        NSString *key = [alert.textFields.firstObject.text
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (key.length == 0) {
            UIAlertController *warn = [UIAlertController alertControllerWithTitle:@"密钥不能为空"
                                                                         message:@"请输入一个至少 1 位的密钥。"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
            [warn addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:warn animated:YES completion:nil];
            return;
        }
        [AISettings setActivationKey:key forAccount:usr];
        [self refreshActivationLabel];
    }]];
    if (activated) {
        [alert addAction:[UIAlertAction actionWithTitle:@"停用本账号"
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(UIAlertAction *action) {
            [AISettings deactivateAccount:usr];
            [self refreshActivationLabel];
        }]];
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)profileListTapped {
    AIProfileListViewController *list = [[AIProfileListViewController alloc] init];
    if (self.navigationController) {
        [self.navigationController pushViewController:list animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
        [self presentViewController:nav animated:YES completion:nil];
    }
}

@end
