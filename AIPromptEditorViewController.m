
#import "AIPromptEditorViewController.h"
#import "AISettings.h"
#import "AIConfig.h"
#import "AIContext.h"
#import "AIProfileListViewController.h"

@interface WeChatAIHandler : NSObject
+ (NSString *)statusString;
+ (NSString *)selfUsrName;
+ (BOOL)isActivatedForCurrentAccount;
@end

typedef NS_ENUM(NSInteger, AISettingsPageKind) {
    AISettingsPageKindHome = 0,
    AISettingsPageKindPrompts,
    AISettingsPageKindAdvanced,
    AISettingsPageKindData,
};

static NSString *AITrim(NSString *text) {
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *AIMaskKey(NSString *key) {
    if (key.length == 0) return @"未填写";
    if (key.length <= 8) return @"已填写";
    return [NSString stringWithFormat:@"%@****%@", [key substringToIndex:4], [key substringFromIndex:key.length - 4]];
}

static NSString *AIProviderKey(NSString *baseURL) {
    NSString *lower = AITrim(baseURL).lowercaseString;
    if ([lower containsString:@"deepseek.com"]) return @"deepseek";
    if ([lower containsString:@"bigmodel.cn"]) return @"zhipu";
    return @"custom";
}

static NSString *AIProviderTitle(NSString *baseURL) {
    NSString *key = AIProviderKey(baseURL);
    if ([key isEqualToString:@"deepseek"]) return @"DeepSeek";
    if ([key isEqualToString:@"zhipu"]) return @"智谱AI";
    return @"自定义";
}

static NSString *AIProviderBaseURL(NSString *provider) {
    if ([provider isEqualToString:@"zhipu"]) return @"https://open.bigmodel.cn/api/paas/v4";
    return @"https://api.deepseek.com";
}

static NSString *AIProviderModel(NSString *provider) {
    if ([provider isEqualToString:@"zhipu"]) return @"glm-4-flash";
    return @"deepseek-v4-flash";
}

static NSArray<NSString *> *AIProviderModels(NSString *provider) {
    if ([provider isEqualToString:@"zhipu"]) return @[@"glm-4-flash", @"glm-4-air", @"glm-4-plus"];
    return @[@"deepseek-v4-flash", @"deepseek-v4-pro"];
}

static NSString *AIModeTitle(NSString *mode) {
    return [mode isEqualToString:@"trigger"] ? @"手动触发" : @"自动回复";
}

static NSString *AIShortBaseURL(NSString *baseURL) {
    NSString *trimmed = AITrim(baseURL);
    if (trimmed.length == 0) return @"未设置";
    NSURL *url = [NSURL URLWithString:trimmed];
    if (url.host.length > 0) return url.path.length > 1 ? [NSString stringWithFormat:@"%@%@", url.host, url.path] : url.host;
    return trimmed;
}

static NSString *AIStateSummary(NSString *current, NSString *defaultText) {
    if (current.length == 0 && defaultText.length == 0) return @"空白";
    if ([current isEqualToString:defaultText]) return @"默认";
    return [NSString stringWithFormat:@"已自定义 · %lu 字", (unsigned long)current.length];
}

@interface AIModalTextEditorController : UIViewController <UITextViewDelegate>
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, copy) NSString *placeholderText;
@property (nonatomic, copy) NSString *hintText;
@property (nonatomic, copy) NSString *resetText;
@property (nonatomic, copy) NSString *resetTitle;
@property (nonatomic, copy) void (^saveHandler)(NSString *text);
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@end

@implementation AIModalTextEditorController

- (instancetype)initWithTitle:(NSString *)title
                  initialText:(NSString *)initialText
                  placeholder:(NSString *)placeholder
                         hint:(NSString *)hint
                    resetText:(NSString *)resetText
                   resetTitle:(NSString *)resetTitle
                  saveHandler:(void (^)(NSString *text))saveHandler {
    self = [super init];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        self.titleText = title;
        self.initialText = initialText ?: @"";
        self.placeholderText = placeholder ?: @"";
        self.hintText = hint ?: @"";
        self.resetText = resetText;
        self.resetTitle = resetTitle ?: @"恢复默认";
        self.saveHandler = saveHandler;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];

    UIBlurEffectStyle style = UIBlurEffectStyleSystemMaterial;
    if (@available(iOS 13.0, *)) style = UIBlurEffectStyleSystemMaterial;
    else style = UIBlurEffectStyleLight;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:style]];
    blur.frame = self.view.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:blur];

    UIButton *back = [UIButton buttonWithType:UIButtonTypeCustom];
    back.frame = self.view.bounds;
    back.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [back addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:back];

    self.cardView = [[UIView alloc] initWithFrame:CGRectZero];
    self.cardView.backgroundColor = [UIColor systemBackgroundColor];
    self.cardView.layer.cornerRadius = 24;
    self.cardView.layer.masksToBounds = YES;
    [self.view addSubview:self.cardView];

    UIView *handle = [[UIView alloc] initWithFrame:CGRectZero];
    handle.tag = 1;
    handle.backgroundColor = [UIColor systemGray4Color];
    handle.layer.cornerRadius = 2.5;
    [self.cardView addSubview:handle];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.tag = 2;
    title.text = self.titleText;
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    title.textAlignment = NSTextAlignmentCenter;
    [self.cardView addSubview:title];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.tag = 3;
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    cancel.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:cancel];

    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    save.tag = 4;
    [save setTitle:@"保存" forState:UIControlStateNormal];
    save.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [save addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:save];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    reset.tag = 5;
    [reset setTitle:self.resetTitle forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    reset.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    reset.layer.cornerRadius = 14;
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:reset];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectZero];
    hint.tag = 6;
    hint.text = self.hintText;
    hint.font = [UIFont systemFontOfSize:13];
    hint.textColor = [UIColor secondaryLabelColor];
    hint.numberOfLines = 0;
    [self.cardView addSubview:hint];

    UIView *editorBg = [[UIView alloc] initWithFrame:CGRectZero];
    editorBg.tag = 7;
    editorBg.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    editorBg.layer.cornerRadius = 18;
    [self.cardView addSubview:editorBg];

    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.font = [UIFont systemFontOfSize:16];
    self.textView.delegate = self;
    self.textView.text = self.initialText;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.spellCheckingType = UITextSpellCheckingTypeNo;
    [editorBg addSubview:self.textView];

    self.placeholderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.placeholderLabel.text = self.placeholderText;
    self.placeholderLabel.textColor = [UIColor placeholderTextColor];
    self.placeholderLabel.font = [UIFont systemFontOfSize:16];
    self.placeholderLabel.numberOfLines = 0;
    [editorBg addSubview:self.placeholderLabel];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self layoutCard];
    [self.textView becomeFirstResponder];
    [self refreshPlaceholder];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutCard];
}

- (void)layoutCard {
    CGFloat width = self.view.bounds.size.width;
    CGFloat cardWidth = MIN(width - 32, 520);
    CGFloat cardHeight = 430;
    self.cardView.frame = CGRectMake((width - cardWidth) / 2.0,
                                     (self.view.bounds.size.height - cardHeight) / 2.0,
                                     cardWidth,
                                     cardHeight);
    UIView *handle = [self.cardView viewWithTag:1];
    UILabel *title = [self.cardView viewWithTag:2];
    UIButton *cancel = [self.cardView viewWithTag:3];
    UIButton *save = [self.cardView viewWithTag:4];
    UIButton *reset = [self.cardView viewWithTag:5];
    UILabel *hint = [self.cardView viewWithTag:6];
    UIView *editorBg = [self.cardView viewWithTag:7];

    handle.frame = CGRectMake((cardWidth - 44) / 2.0, 10, 44, 5);
    cancel.frame = CGRectMake(12, 24, 56, 32);
    save.frame = CGRectMake(cardWidth - 68, 24, 56, 32);
    title.frame = CGRectMake(72, 24, cardWidth - 144, 32);
    reset.frame = CGRectMake(cardWidth - 98, 66, 82, 28);

    CGSize hintSize = [hint sizeThatFits:CGSizeMake(cardWidth - 32, CGFLOAT_MAX)];
    hint.frame = CGRectMake(16, 102, cardWidth - 32, hintSize.height);

    CGFloat editorTop = CGRectGetMaxY(hint.frame) + 12;
    editorBg.frame = CGRectMake(12, editorTop, cardWidth - 24, cardHeight - editorTop - 18);
    self.textView.frame = CGRectMake(12, 10, editorBg.bounds.size.width - 24, editorBg.bounds.size.height - 20);
    self.placeholderLabel.frame = CGRectMake(17, 18, editorBg.bounds.size.width - 34, 44);
}

- (void)refreshPlaceholder {
    self.placeholderLabel.hidden = self.textView.text.length > 0;
}

- (void)textViewDidChange:(UITextView *)textView {
    [self refreshPlaceholder];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetTapped {
    self.textView.text = self.resetText ?: @"";
    [self refreshPlaceholder];
}

- (void)saveTapped {
    if (self.saveHandler) self.saveHandler(self.textView.text ?: @"");
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface AIPromptEditorViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) AISettingsPageKind pageKind;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) BOOL activationPrompted;
@end

@implementation AIPromptEditorViewController

- (instancetype)init {
    return [self initWithPageKind:AISettingsPageKindHome];
}

- (instancetype)initWithPageKind:(AISettingsPageKind)pageKind {
    self = [super init];
    if (self) _pageKind = pageKind;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [AISettings setCurrentAccount:[WeChatAIHandler selfUsrName]];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = [self titleForPage];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.view addSubview:self.tableView];
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 4;

    if (self.pageKind == AISettingsPageKindHome) {
        BOOL isModal = (self.navigationController.presentingViewController != nil);
        if (isModal) {
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                                                     style:UIBarButtonItemStylePlain
                                                                                    target:self
                                                                                    action:@selector(cancelTapped)];
        }
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成"
                                                                                   style:UIBarButtonItemStyleDone
                                                                                  target:self
                                                                                  action:@selector(saveTapped)];
        [self rebuildFooter];
    }
}

- (NSString *)titleForPage {
    switch (self.pageKind) {
        case AISettingsPageKindPrompts: return @"提示词与风格";
        case AISettingsPageKindAdvanced: return @"高级参数";
        case AISettingsPageKindData: return @"数据与备份";
        default: return @"AI 设置";
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [AISettings setCurrentAccount:[WeChatAIHandler selfUsrName]];
    [self.tableView reloadData];
    if (self.pageKind == AISettingsPageKindHome) [self rebuildFooter];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.pageKind == AISettingsPageKindHome && ![WeChatAIHandler isActivatedForCurrentAccount] && !self.activationPrompted) {
        self.activationPrompted = YES;
        [self showActivationPrompt];
    }
}

- (void)rebuildFooter {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 72)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, footer.bounds.size.width - 32, 40)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = [NSString stringWithFormat:@"微信 AI 助手 v%@", kAITweakVersion];
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    [footer addSubview:label];
    self.tableView.tableFooterView = footer;
}

- (void)cancelTapped { [self dismissOrPop]; }
- (void)saveTapped { [self dismissOrPop]; }

- (void)dismissOrPop {
    if (self.navigationController.presentingViewController && self.navigationController.viewControllers.firstObject == self) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else if (self.presentingViewController && !self.navigationController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.pageKind == AISettingsPageKindHome) return 4;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.pageKind == AISettingsPageKindHome) {
        if (section == 0) return 4;
        if (section == 1) return 4;
        if (section == 2) return 5;
        return 3;
    }
    if (self.pageKind == AISettingsPageKindPrompts) return 3;
    if (self.pageKind == AISettingsPageKindAdvanced) return 3;
    return 4;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.pageKind == AISettingsPageKindHome) {
        if (section == 0) return @"状态与会话";
        if (section == 1) return @"模型与接口";
        if (section == 2) return @"像本人聊天";
        return @"更多设置";
    }
    if (self.pageKind == AISettingsPageKindPrompts) return @"越像本人，越要少填规则";
    if (self.pageKind == AISettingsPageKindAdvanced) return @"生成参数";
    return @"数据工具";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.pageKind == AISettingsPageKindHome && section == 1) return @"支持 DeepSeek、智谱AI，以及任何 OpenAI 兼容接口。";
    if (self.pageKind == AISettingsPageKindPrompts) return @"优先级：当前聊天 > 本人最近发言 > 已学习语气 > 基础信息。这里主要补充 AI 自己读不出来的内容。";
    if (self.pageKind == AISettingsPageKindAdvanced) return @"建议先用默认值，只有明确想调整生成风格时再改。";
    if (self.pageKind == AISettingsPageKindData) return @"恢复默认会保留 API Key、激活状态和学习档案；清空记忆则只清聊天上下文与学习结果。";
    return nil;
}

- (BOOL)isSwitchRow:(NSIndexPath *)indexPath {
    if (self.pageKind != AISettingsPageKindHome) return NO;
    if (indexPath.section == 0 && indexPath.row == 0) return YES;
    if (indexPath.section == 2 && indexPath.row >= 2) return YES;
    return NO;
}

- (NSInteger)switchTag:(NSIndexPath *)indexPath {
    return indexPath.section * 100 + indexPath.row;
}

- (UITableViewCell *)baseCell:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"SettingCell"];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self baseCell:tableView];
    if ([self isSwitchRow:indexPath]) {
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
        sw.tag = [self switchTag:indexPath];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.section == 0 && indexPath.row == 0) {
            cell.textLabel.text = @"机器人开关";
            sw.enabled = [WeChatAIHandler isActivatedForCurrentAccount];
            sw.on = sw.enabled && [AISettings enabled];
            cell.detailTextLabel.text = sw.enabled ? nil : @"需先激活";
        } else if (indexPath.section == 2 && indexPath.row == 2) {
            cell.textLabel.text = @"群聊只回提问";
            sw.on = [AISettings groupQuestionOnly];
        } else if (indexPath.section == 2 && indexPath.row == 3) {
            cell.textLabel.text = @"表情包轻回复";
            sw.on = [AISettings stickerLightReply];
        } else {
            cell.textLabel.text = @"模拟打字";
            sw.on = [AISettings typingSimulation];
        }
        return cell;
    }

    if (self.pageKind == AISettingsPageKindHome) {
        if (indexPath.section == 0) {
            if (indexPath.row == 1) {
                cell.textLabel.text = @"激活状态";
                cell.detailTextLabel.text = [WeChatAIHandler isActivatedForCurrentAccount] ? @"已激活" : @"未激活";
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"AI 状态";
                cell.detailTextLabel.text = @"查看";
            } else {
                cell.textLabel.text = @"学习档案";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld 个", (long)[AISettings styleProfileCount]];
            }
            return cell;
        }
        if (indexPath.section == 1) {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"服务商";
                cell.detailTextLabel.text = AIProviderTitle([AISettings baseURL]);
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"API Key";
                cell.detailTextLabel.text = AIMaskKey([AISettings apiKey]);
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"接口地址";
                cell.detailTextLabel.text = AIShortBaseURL([AISettings baseURL]);
            } else {
                cell.textLabel.text = @"模型";
                cell.detailTextLabel.text = [AISettings model];
            }
            return cell;
        }
        if (indexPath.section == 2) {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"回复模式";
                cell.detailTextLabel.text = AIModeTitle([AISettings replyMode]);
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"思考延迟";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f 秒", [AISettings replyDelay]];
            }
            return cell;
        }
        if (indexPath.row == 0) {
            cell.textLabel.text = @"像本人聊天";
            cell.detailTextLabel.text = @"最近发言 / 语气 / 基础信息";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"高级参数";
            cell.detailTextLabel.text = @"温度 / 惩罚项";
        } else {
            cell.textLabel.text = @"数据与备份";
            cell.detailTextLabel.text = @"备份 / 恢复 / 清理";
        }
        return cell;
    }

    if (self.pageKind == AISettingsPageKindPrompts) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"自动回复提示词";
            cell.detailTextLabel.text = AIStateSummary([AISettings autoSystemPrompt], kAIAutoSystemPrompt);
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"聊天风格样本";
            cell.detailTextLabel.text = AIStateSummary([AISettings styleSamples], kAIStyleSamplesDefault);
        } else {
            cell.textLabel.text = @"基础信息";
            cell.detailTextLabel.text = AIStateSummary([AISettings userProfile], kAIUserProfile);
        }
        return cell;
    }

    if (self.pageKind == AISettingsPageKindAdvanced) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Temperature";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f", [AISettings temperature]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Frequency Penalty";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f", [AISettings frequencyPenalty]];
        } else {
            cell.textLabel.text = @"Presence Penalty";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f", [AISettings presencePenalty]];
        }
        return cell;
    }

    if (indexPath.row == 0) {
        cell.textLabel.text = @"导出备份";
        cell.detailTextLabel.text = @"保存到 Documents";
    } else if (indexPath.row == 1) {
        cell.textLabel.text = @"恢复最近备份";
        cell.detailTextLabel.text = [AISettings latestBackupPath] ? @"可恢复" : @"暂无备份";
    } else if (indexPath.row == 2) {
        cell.textLabel.text = @"清空全部记忆";
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.detailTextLabel.text = @"不可恢复";
    } else {
        cell.textLabel.text = @"恢复默认设置";
        cell.detailTextLabel.text = @"保留 Key 和档案";
    }
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    NSInteger section = sender.tag / 100;
    NSInteger row = sender.tag % 100;
    if (section == 0 && row == 0) [AISettings setEnabled:sender.on];
    else if (section == 2 && row == 2) [AISettings setGroupQuestionOnly:sender.on];
    else if (section == 2 && row == 3) [AISettings setStickerLightReply:sender.on];
    else if (section == 2 && row == 4) [AISettings setTypingSimulation:sender.on];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isSwitchRow:indexPath]) return;

    if (self.pageKind == AISettingsPageKindHome) {
        if (indexPath.section == 0) {
            if (indexPath.row == 1) [self activationTapped];
            else if (indexPath.row == 2) [self statusTapped];
            else if (indexPath.row == 3) [self profileListTapped];
            return;
        }
        if (indexPath.section == 1) {
            if (indexPath.row == 0) [self providerTapped];
            else if (indexPath.row == 1) [self apiKeyTapped];
            else if (indexPath.row == 2) [self baseURLTapped];
            else [self modelTapped];
            return;
        }
        if (indexPath.section == 2) {
            if (indexPath.row == 0) [self modeTapped];
            else if (indexPath.row == 1) [self delayTapped];
            return;
        }
        if (indexPath.row == 0) [self pushPage:AISettingsPageKindPrompts];
        else if (indexPath.row == 1) [self pushPage:AISettingsPageKindAdvanced];
        else [self pushPage:AISettingsPageKindData];
        return;
    }

    if (self.pageKind == AISettingsPageKindPrompts) {
        if (indexPath.row == 0) {
            [self showTextEditorWithTitle:@"自动回复提示词" initial:[AISettings autoSystemPrompt] placeholder:@"输入自动回复提示词" hint:@"AI 自动回复时会严格参考这里的角色设定和回复约束。" resetText:kAIAutoSystemPrompt resetTitle:@"恢复默认" save:^(NSString *text) { [AISettings setAutoSystemPrompt:text]; [self.tableView reloadData]; }];
        } else if (indexPath.row == 1) {
            [self showTextEditorWithTitle:@"聊天风格样本" initial:[AISettings styleSamples] placeholder:@"按 Q:/A: 格式填写真实聊天样本" hint:@"建议使用 Q: 对方说 / A: 我说 的格式，AI 学得更稳。" resetText:kAIStyleSamplesDefault resetTitle:@"恢复默认" save:^(NSString *text) { [AISettings setStyleSamples:text]; [self.tableView reloadData]; }];
        } else {
            [self showTextEditorWithTitle:@"基础信息" initial:[AISettings userProfile] placeholder:@"写你的称呼、家庭、口味、常去地点、口头禅等" hint:@"这些信息只属于“你本人”，AI 聊天会优先以这里为准。" resetText:kAIUserProfile resetTitle:@"清空" save:^(NSString *text) { [AISettings setUserProfile:text]; [self.tableView reloadData]; }];
        }
        return;
    }

    if (self.pageKind == AISettingsPageKindAdvanced) {
        if (indexPath.row == 0) [self showNumberEditorWithTitle:@"Temperature" value:[AISettings temperature] hint:@"0 ~ 2，越高越放飞。默认 0.50" resetValue:kAIRequestTemperature save:^(double v) { [AISettings setTemperature:(v >= 0 && v <= 2) ? v : kAIRequestTemperature]; [self.tableView reloadData]; }];
        else if (indexPath.row == 1) [self showNumberEditorWithTitle:@"Frequency Penalty" value:[AISettings frequencyPenalty] hint:@"0 ~ 2，越高越少重复。默认 0.40" resetValue:kAIRequestFrequencyPenalty save:^(double v) { [AISettings setFrequencyPenalty:(v >= 0 && v <= 2) ? v : kAIRequestFrequencyPenalty]; [self.tableView reloadData]; }];
        else [self showNumberEditorWithTitle:@"Presence Penalty" value:[AISettings presencePenalty] hint:@"0 ~ 2，越高越愿意聊新内容。默认 0.40" resetValue:kAIRequestPresencePenalty save:^(double v) { [AISettings setPresencePenalty:(v >= 0 && v <= 2) ? v : kAIRequestPresencePenalty]; [self.tableView reloadData]; }];
        return;
    }

    if (indexPath.row == 0) [self backupTapped];
    else if (indexPath.row == 1) [self restoreTapped];
    else if (indexPath.row == 2) [self memoryTapped];
    else [self resetDefaultsTapped];
}

- (void)pushPage:(AISettingsPageKind)kind {
    AIPromptEditorViewController *vc = [[AIPromptEditorViewController alloc] initWithPageKind:kind];
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)showTextEditorWithTitle:(NSString *)title initial:(NSString *)initial placeholder:(NSString *)placeholder hint:(NSString *)hint resetText:(NSString *)resetText resetTitle:(NSString *)resetTitle save:(void (^)(NSString *text))save {
    AIModalTextEditorController *vc = [[AIModalTextEditorController alloc] initWithTitle:title initialText:initial placeholder:placeholder hint:hint resetText:resetText resetTitle:resetTitle saveHandler:save];
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)showNumberEditorWithTitle:(NSString *)title value:(double)value hint:(NSString *)hint resetValue:(double)resetValue save:(void (^)(double v))save {
    NSString *initial = [NSString stringWithFormat:@"%.2f", value];
    NSString *reset = [NSString stringWithFormat:@"%.2f", resetValue];
    [self showTextEditorWithTitle:title initial:initial placeholder:@"输入数值" hint:hint resetText:reset resetTitle:@"默认值" save:^(NSString *text) { save([text doubleValue]); }];
}

- (void)statusTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AI 状态" message:[WeChatAIHandler statusString] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)activationTapped {
    if (![WeChatAIHandler isActivatedForCurrentAccount]) { [self showActivationPrompt]; return; }
    NSString *usr = [WeChatAIHandler selfUsrName];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"激活密钥" message:[NSString stringWithFormat:@"当前微信账号（%@）已激活。", usr] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"停用本账号" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [AISettings deactivateAccount:usr]; [self.tableView reloadData]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showActivationPrompt {
    if ([WeChatAIHandler isActivatedForCurrentAccount]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入激活密钥" message:@"当前微信账号未激活，输入密钥后才能使用 AI 助手。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"输入密钥"; tf.secureTextEntry = YES; tf.autocapitalizationType = UITextAutocapitalizationTypeNone; tf.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { if (self.pageKind == AISettingsPageKindHome) [self dismissOrPop]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *key = AITrim(alert.textFields.firstObject.text);
        if (![key isEqualToString:kAIActivationKey]) {
            UIAlertController *warn = [UIAlertController alertControllerWithTitle:@"密钥错误" message:@"输入的密钥不正确，请重试。" preferredStyle:UIAlertControllerStyleAlert];
            [warn addAction:[UIAlertAction actionWithTitle:@"重新输入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self showActivationPrompt]; }]];
            [self presentViewController:warn animated:YES completion:nil];
            return;
        }
        [AISettings setActivationKey:key forAccount:[WeChatAIHandler selfUsrName]];
        [self.tableView reloadData];
        UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"激活成功" message:@"已激活，现在可以正常使用 AI 助手了。" preferredStyle:UIAlertControllerStyleAlert];
        [ok addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ok animated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)profileListTapped {
    AIProfileListViewController *list = [[AIProfileListViewController alloc] init];
    if (self.navigationController) [self.navigationController pushViewController:list animated:YES];
    else [self presentViewController:[[UINavigationController alloc] initWithRootViewController:list] animated:YES completion:nil];
}

- (void)providerTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择服务商" message:@"会自动填充建议接口地址，并切到该服务商推荐模型。" preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"DeepSeek" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [AISettings setBaseURL:AIProviderBaseURL(@"deepseek")]; [AISettings setModel:AIProviderModel(@"deepseek")]; [self.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"智谱AI" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [AISettings setBaseURL:AIProviderBaseURL(@"zhipu")]; [AISettings setModel:AIProviderModel(@"zhipu")]; [self.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"自定义" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self baseURLTapped]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, 120, 1, 1); }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)apiKeyTapped { [self showTextEditorWithTitle:@"API Key" initial:[AISettings apiKey] placeholder:@"输入 API Key" hint:@"只保存在这台设备的本地 Keychain，不会写进代码。" resetText:@"" resetTitle:@"清空" save:^(NSString *text) { [AISettings setApiKey:AITrim(text)]; [self.tableView reloadData]; }]; }
- (void)baseURLTapped { [self showTextEditorWithTitle:@"接口地址" initial:[AISettings baseURL] placeholder:@"例如 https://api.deepseek.com" hint:@"填写 OpenAI 兼容接口根地址，不需要自己拼 /chat/completions。" resetText:kAIBaseURL resetTitle:@"默认值" save:^(NSString *text) { [AISettings setBaseURL:AITrim(text)]; [self.tableView reloadData]; }]; }
- (void)modelTapped {
    NSString *provider = AIProviderKey([AISettings baseURL]);
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择模型" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *name in AIProviderModels(provider)) {
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [AISettings setModel:name]; [self.tableView reloadData]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"自定义…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self showTextEditorWithTitle:@"自定义模型" initial:[AISettings model] placeholder:@"输入完整模型名" hint:@"例如 deepseek-v4-pro、glm-4-plus，需你的接口本身支持。" resetText:AIProviderModel(provider) resetTitle:@"推荐值" save:^(NSString *text) { NSString *name = AITrim(text); if (name.length > 0) { [AISettings setModel:name]; [self.tableView reloadData]; } }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, 160, 1, 1); }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)modeTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"回复模式" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"自动回复" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [AISettings setReplyMode:@"auto"]; [self.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"手动触发（@AI 开头才回）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [AISettings setReplyMode:@"trigger"]; [self.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, 200, 1, 1); }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)delayTapped { [self showTextEditorWithTitle:@"思考延迟" initial:[NSString stringWithFormat:@"%.1f", [AISettings replyDelay]] placeholder:@"输入秒数" hint:@"建议 0.3 ~ 3 秒，过高会显得拖沓。" resetText:[NSString stringWithFormat:@"%.1f", kAIReplyDelaySeconds] resetTitle:@"默认值" save:^(NSString *text) { double delay = [text doubleValue]; [AISettings setReplyDelay:(delay > 0 && delay <= 30) ? delay : kAIReplyDelaySeconds]; [self.tableView reloadData]; }]; }

- (void)backupTapped {
    NSString *path = [AISettings writeBackupToFile];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:(path ? @"✅ 备份成功" : @"❌ 备份失败") message:(path ? [NSString stringWithFormat:@"已写入：\n%@", path] : @"写入备份文件出错，请稍后重试。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restoreTapped {
    NSString *path = [AISettings latestBackupPath];
    if (path.length == 0) {
        UIAlertController *warn = [UIAlertController alertControllerWithTitle:@"没有找到备份" message:@"请先执行一次导出备份。" preferredStyle:UIAlertControllerStyleAlert];
        [warn addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:warn animated:YES completion:nil];
        return;
    }
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"恢复最近备份" message:[NSString stringWithFormat:@"将使用这个文件覆盖当前设置：\n%@", path.lastPathComponent] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        BOOL ok = [AISettings restoreFromFile:path];
        [self.tableView reloadData];
        UIAlertController *result = [UIAlertController alertControllerWithTitle:(ok ? @"✅ 恢复成功" : @"❌ 恢复失败") message:(ok ? @"配置已恢复，请重新检查关键设置。" : @"备份文件无效或读取失败。") preferredStyle:UIAlertControllerStyleAlert];
        [result addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:result animated:YES completion:nil];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)memoryTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空全部记忆" message:@"将清空所有会话的聊天上下文和已学习的风格档案，无法恢复。确定继续吗？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[AIContext shared] clearAll];
        [AISettings clearAllStyleProfiles];
        [AISettings clearAllStyleCorpora];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetDefaultsTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认设置" message:@"会恢复接口、模型、模式、提示词和高级参数的默认值，但保留 API Key、激活状态和学习档案。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [AISettings setEnabled:YES];
        [AISettings setBaseURL:kAIBaseURL];
        [AISettings setModel:kAIModel];
        [AISettings setReplyMode:kAIReplyMode];
        [AISettings setReplyDelay:kAIReplyDelaySeconds];
        [AISettings setTemperature:kAIRequestTemperature];
        [AISettings setFrequencyPenalty:kAIRequestFrequencyPenalty];
        [AISettings setPresencePenalty:kAIRequestPresencePenalty];
        [AISettings setTypingSimulation:YES];
        [AISettings setGroupQuestionOnly:YES];
        [AISettings setStickerLightReply:NO];
        [AISettings setAutoSystemPrompt:kAIAutoSystemPrompt];
        [AISettings setStyleSamples:kAIStyleSamplesDefault];
        [AISettings setUserProfile:kAIUserProfile];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end


