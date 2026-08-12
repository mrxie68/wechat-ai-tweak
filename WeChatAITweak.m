//
//  WeChatAITweak.m
//  微信 AI 助手插件
//
//  纯 Objective-C 运行时实现，不依赖 CydiaSubstrate / Theos，
//  所以同一个 dylib：
//    - TrollStore + TrollFools 直接注入微信
//    - 越狱环境放进 DynamicLibraries 由 MobileSubstrate 加载
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <time.h>
#import <stdlib.h>
#import "AIConfig.h"
#import "AIContext.h"
#import "AIAPIClient.h"
#import "AISettings.h"
#import "AIPromptEditorViewController.h"

#pragma mark - 微信私有接口声明（class-dump 常见签名）

@interface CMessageWrap : NSObject
@property (nonatomic, retain) NSString *m_nsContent;
@property (nonatomic, retain) NSString *m_nsFromUsr;
@property (nonatomic, retain) NSString *m_nsToUsr;
@property (nonatomic, assign) long long m_nsMsgSvrID;
@property (nonatomic, assign) unsigned int m_uiMessageType;
@property (nonatomic, assign) unsigned int m_uiCreateTime;
@property (nonatomic, assign) unsigned int m_uiStatus;
- (id)initWithMsgType:(long long)type;
- (id)initWithMsgType:(long long)type nsFromUsr:(NSString *)fromUsr;
@end

@interface CMessageMgr : NSObject
- (void)AsyncOnAddMsg:(id)arg1 MsgWrap:(CMessageWrap *)wrap;
- (void)MainThreadNotifyToExt:(NSDictionary *)ext;
- (void)SendTextMessage:(NSString *)content toUsrName:(NSString *)usrName;
- (void)SendMessage:(id)msgWrap isSendByWeChat:(BOOL)flag;
- (void)AddMsg:(id)arg1 MsgWrap:(id)arg2;
@end

@interface WCMessageService : NSObject
- (void)SendMessage:(id)msgWrap isSendByWeChat:(BOOL)flag;
@end

@interface SettingUtil : NSObject
+ (id)getCurUsrName;
@end

// wcplugins（插件管理/收纳）的注册接口
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title
                            version:(NSString *)version
                         controller:(NSString *)controller;
- (void)registerSwitchWithTitle:(NSString *)title key:(NSString *)key;
@end

// 辅助：递归查找 UITableView
@interface AIDiagnostics : NSObject
+ (UITableView *)findTableViewInView:(UIView *)view;
@end

@interface CContact : NSObject
@property (nonatomic, retain) NSString *m_nsUsrName;
@end

@interface CContactMgr : NSObject
- (CContact *)getSelfContact;
@end

@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)cls;
@end

#pragma mark - 微信服务封装

static CMessageMgr *wechatMessageMgr(void) {
    Class centerCls = NSClassFromString(@"MMServiceCenter");
    if (!centerCls) return nil;
    id center = [(id)centerCls defaultCenter];
    if (!center) return nil;
    return (CMessageMgr *)[center getService:NSClassFromString(@"CMessageMgr")];
}

static NSString *wechatSelfUsrName(void) {
    Class centerCls = NSClassFromString(@"MMServiceCenter");
    if (!centerCls) return nil;
    id center = [(id)centerCls defaultCenter];
    if (!center) return nil;
    id contactMgr = [center getService:NSClassFromString(@"CContactMgr")];
    NSString *usrName = nil;
    // 防御：私有类接口以 respondsToSelector 兜底，避免版本差异闪退
    if ([contactMgr respondsToSelector:@selector(getSelfContact)]) {
        CContact *selfContact = [contactMgr getSelfContact];
        if ([selfContact respondsToSelector:@selector(m_nsUsrName)]) {
            usrName = [selfContact m_nsUsrName];
        }
    }
    if (usrName.length == 0) {
        // 兜底：用 SettingUtil 拿当前微信号
        Class settingUtil = NSClassFromString(@"SettingUtil");
        if (settingUtil && [settingUtil respondsToSelector:@selector(getCurUsrName)]) {
            usrName = [(id)settingUtil getCurUsrName];
        }
    }
    return usrName;
}

static BOOL isAutoMode(void) {
    return [[AISettings replyMode] isEqualToString:@"auto"];
}

// 白名单：空 = 所有会话都允许触发
static BOOL isChatAllowed(NSString *chatId) {
    NSString *raw = kAIAllowedChats;
    if (raw.length == 0) return YES;

    NSArray *allowed = [raw componentsSeparatedByString:@","];
    for (NSString *item in allowed) {
        NSString *trimmed = [item stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed isEqualToString:chatId]) return YES;
    }
    return NO;
}

// 尝试用微信自己的消息接口拉取某个会话最近 N 条文字消息（运行时探测，找不到就返回空）
static NSArray<NSString *> *fetchRecentTexts(NSString *chatId, NSInteger limit) {
    NSMutableArray *texts = [NSMutableArray array];
    CMessageMgr *mgr = wechatMessageMgr();
    if (!mgr || chatId.length == 0) return texts;

    // 路径 1：GetFirstMsg: / GetNextMsg:fromMsg:（同步遍历，class-dump 常见签名）
    if ([mgr respondsToSelector:@selector(GetFirstMsg:)] &&
        [mgr respondsToSelector:@selector(GetNextMsg:fromMsg:)]) {
        @try {
            id msg = [mgr GetFirstMsg:chatId];
            NSInteger guard = 0;
            while (msg && guard < 3000) {
                guard++;
                NSInteger type = 0;
                if ([msg respondsToSelector:@selector(m_uiMessageType)]) {
                    type = [msg m_uiMessageType];
                }
                if (type == 1) {
                    NSString *content = [msg m_nsContent] ?: @"";
                    if (content.length > 0 && ![content hasPrefix:@"<msg"]) {
                        [texts addObject:content];
                    }
                }
                id next = [mgr GetNextMsg:chatId fromMsg:msg];
                if (!next || next == msg) break;
                msg = next;
            }
            NSLog(kAITweakLogPrefix "历史消息拉取成功（GetFirstMsg 路径），%lu 条", (unsigned long)texts.count);
        } @catch (NSException *exception) {
            [texts removeAllObjects];
            NSLog(kAITweakLogPrefix "GetFirstMsg 路径异常: %@", exception);
        }
    } else {
        NSLog(kAITweakLogPrefix "微信版本没有 GetFirstMsg/GetNextMsg 接口，历史记录需另寻路径");
    }

    // 只保留最后 limit 条（按遍历顺序的“最近”）
    if (texts.count > limit) {
        [texts removeObjectsInRange:NSMakeRange(0, texts.count - limit)];
    }
    return texts;
}

// ===== 消息去重（新旧两条收消息 hook 同时安装，防止同一条消息处理两次）=====
static NSObject *g_dedupLock = nil;
static NSMutableSet *g_seenKeys = nil;
static NSMutableArray *g_seenOrder = nil;

static NSString *messageKey(CMessageWrap *wrap) {
    // 优先用服务器消息 ID 去重：两条 hook 收到的是同一条消息，ID 相同；
    // 避免“同一秒发两条一样的话”被误判成重复而漏回
    if ([wrap respondsToSelector:@selector(m_nsMsgSvrID)]) {
        @try {
            long long svrId = [wrap m_nsMsgSvrID];
            if (svrId != 0) {
                NSString *from = [wrap m_nsFromUsr] ?: @"";
                return [NSString stringWithFormat:@"%@|%lld", from, svrId];
            }
        } @catch (NSException *exception) {
            // 忽略，走下面的兜底 key
        }
    }
    NSString *from = [wrap m_nsFromUsr] ?: @"";
    NSString *content = [wrap m_nsContent] ?: @"";
    unsigned int createTime = 0;
    if ([wrap respondsToSelector:@selector(m_uiCreateTime)]) {
        createTime = (unsigned int)[wrap m_uiCreateTime];
    }
    return [NSString stringWithFormat:@"%@|%@|%u", from, content, createTime];
}

static BOOL isDuplicateMessage(CMessageWrap *wrap) {
    NSString *key = messageKey(wrap);
    if (key.length == 0) return NO;
    @synchronized (g_dedupLock) {
        if ([g_seenKeys containsObject:key]) return YES;
        [g_seenKeys addObject:key];
        [g_seenOrder addObject:key];
        if (g_seenOrder.count > 100) {
            NSString *oldest = [g_seenOrder firstObject];
            [g_seenOrder removeObjectAtIndex:0];
            [g_seenKeys removeObject:oldest];
        }
    }
    return NO;
}

// 找到当前最上层的控制器，用于弹出设置页
static UIViewController *tweakTopViewController(void) {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *window = app.keyWindow;
    if (!window) {
        for (UIWindow *w in app.windows) {
            if (w.isKeyWindow) {
                window = w;
                break;
            }
        }
    }
    if (!window) window = app.windows.firstObject;
    if (!window) return nil;

    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

// hook 安装状态（供 @AI 状态 命令显示）
static BOOL g_hookAsync = NO;
static BOOL g_hookExt = NO;
static BOOL g_hookSend = NO;
// wcplugins 插件管理（收纳）注册状态
static BOOL g_wcpluginsClassFound = NO;
static BOOL g_wcpluginsRegistered = NO;
static BOOL g_wcpluginsControllerRegistered = NO;

#pragma mark - 核心逻辑

@interface WeChatAIHandler : NSObject
@end

@implementation WeChatAIHandler

static NSMutableSet *g_inFlightChats = nil;
static NSMutableSet *g_pendingChats = nil;
static NSString *g_contextAccount = nil;
static void *kAIConfigKey = &kAIConfigKey;          // tableView -> 页面配置
static void *kAISwitchChatKey = &kAISwitchChatKey;  // 开关 -> chatId

// 最近发出的 AI 回复（用于回显去重：发出时已记过上下文，回显不再记第二遍）
static NSObject *g_replyLock = nil;
static NSMutableSet *g_recentReplies = nil;
static NSMutableArray *g_recentReplyOrder = nil;

+ (void)noteReplySent:(NSString *)text chatId:(NSString *)chatId {
    if (text.length == 0 || chatId.length == 0) return;
    NSString *key = [NSString stringWithFormat:@"%@|%@", chatId, text];
    @synchronized (g_replyLock) {
        if (!g_recentReplies) {
            g_recentReplies = [NSMutableSet set];
            g_recentReplyOrder = [NSMutableArray array];
        }
        [g_recentReplies addObject:key];
        [g_recentReplyOrder addObject:key];
        if (g_recentReplyOrder.count > 40) {
            NSString *oldest = [g_recentReplyOrder firstObject];
            [g_recentReplyOrder removeObjectAtIndex:0];
            [g_recentReplies removeObject:oldest];
        }
    }
}

+ (BOOL)isRecentReply:(NSString *)text chatId:(NSString *)chatId {
    if (text.length == 0 || chatId.length == 0) return NO;
    NSString *key = [NSString stringWithFormat:@"%@|%@", chatId, text];
    @synchronized (g_replyLock) {
        return [g_recentReplies containsObject:key];
    }
}

// 账号隔离：检测到当前微信账号变化时清空全部上下文，避免把上一个账号的对话带过去
+ (void)syncContextAccount {
    NSString *usrName = wechatSelfUsrName();
    if (usrName.length == 0) return;
    @synchronized (self) {
        if (g_contextAccount && ![g_contextAccount isEqualToString:usrName]) {
            NSLog(kAITweakLogPrefix "检测到微信账号切换，清空全部上下文");
            [[AIContext shared] clearAll];
        }
        g_contextAccount = usrName;
    }
}

+ (void)handleIncomingMessage:(CMessageWrap *)wrap {
    @try {
        [self syncContextAccount];

        if (![wrap isKindOfClass:NSClassFromString(@"CMessageWrap")]) return;
        unsigned int msgType = [wrap m_uiMessageType];

        NSString *content = [wrap m_nsContent];
        NSString *fromUsr = [wrap m_nsFromUsr];
        NSString *toUsr = [wrap m_nsToUsr];
        if (fromUsr.length == 0) return;

        // 新旧收消息 hook 可能同时触发，去重
        if (isDuplicateMessage(wrap)) return;

        // 判断是不是自己发的消息（文件助手/多端同步的回显）
        NSString *selfUsr = wechatSelfUsrName();
        BOOL isSelf = (selfUsr.length > 0 && [fromUsr isEqualToString:selfUsr]);

        // 会话 id：
        //   自己发的消息 → 发给谁就是哪个会话（文件助手用 toUsr=filehelper）
        //   群聊 → toUsr（@chatroom 结尾）
        //   别人单聊 → fromUsr（对方 wxid）
        BOOL isGroup = [toUsr containsString:@"@chatroom"];
        NSString *chatId = isSelf ? toUsr : (isGroup ? toUsr : fromUsr);

        // 白名单过滤：不在白名单里的会话直接忽略（不读取内容）
        if (!isChatAllowed(chatId)) return;

        // 非文本消息（图片/语音/视频/表情/位置/文件）：不自动回复，
        // 只记一条占位符，让 AI 知道对方发过媒体但不编造看不到的内容
        if (msgType != 1) {
            [self recordMediaPlaceholder:msgType isSelf:isSelf chatId:chatId];
            return;
        }

        if (content.length == 0) return;

        // 自己发的消息：先识别 @AI 命令；不是命令则记进上下文（8.0.5x 没有发送 hook，靠回显记录）
        if (isSelf) {
            // 插件自己刚发出的回复回显：发出时已记过上下文，这里跳过，避免记两遍
            if ([self isRecentReply:content chatId:chatId]) return;
            if ([AISettings enabled] && isAutoMode()) {
                [[AIContext shared] appendAssistant:content chatId:chatId];
            }
            return;
        }

        // 机器人总开关：关闭时别人的消息一律不处理（管理命令只对“自己发的”生效）
        if (![AISettings enabled]) return;

        // 会话级开关：默认全关，只有聊天信息页单独开过的会话才回复
        if (![AISettings chatEnabled:chatId]) return;

        BOOL autoMode = isAutoMode();

        // trigger 模式：只响应 @AI 开头的消息
        if (!autoMode) {
            if ([content hasPrefix:kAITrigger]) {
                [self handleTriggerMessage:content chatId:chatId];
            }
            return;
        }

        // 自动模式：@AI 开头的消息仍按手动命令/提问处理（清空、指定问题）
        if ([content hasPrefix:kAITrigger]) {
            [self handleTriggerMessage:content chatId:chatId];
            return;
        }

        // 自动模式：对方发消息 → 记入上下文 → 自动回复
        [[AIContext shared] appendUser:content chatId:chatId];
        [self enqueueReplyForChat:chatId message:content];
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "处理消息异常: %@", exception);
    }
}

// 媒体消息占位：只记“发了什么类型”，不记内容、不回复
+ (void)recordMediaPlaceholder:(unsigned int)msgType isSelf:(BOOL)isSelf chatId:(NSString *)chatId {
    NSString *name = nil;
    switch (msgType) {
        case 3:  name = @"图片"; break;
        case 34: name = @"语音"; break;
        case 43: name = @"视频"; break;
        case 47: name = @"表情"; break;
        case 48: name = @"位置"; break;
        case 49: name = @"文件/链接"; break;
        default: return; // 系统消息、拍一拍等一律不记录
    }
    if (![AISettings enabled]) return;
    if (![AISettings chatEnabled:chatId]) return;
    if (isSelf && !isAutoMode()) return; // 自己发的媒体只在自动模式下记（和文本一致）

    NSString *placeholder = isSelf
        ? [NSString stringWithFormat:@"（我发了一条%@消息，内容未知）", name]
        : [NSString stringWithFormat:@"（对方发了一条%@消息，内容未知）", name];
    if (isSelf) {
        [[AIContext shared] appendAssistant:placeholder chatId:chatId];
    } else {
        [[AIContext shared] appendUser:placeholder chatId:chatId];
    }
    NSLog(kAITweakLogPrefix "记录媒体占位符(%@): %@", name, chatId);
}

+ (void)handleTriggerMessage:(NSString *)content chatId:(NSString *)chatId {
    @try {
        NSString *question = [content substringFromIndex:kAITrigger.length];
        question = [question stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (question.length == 0) {
            [self sendReply:@"请在 @AI 后加上你的问题，例如：@AI 帮我写一段冒泡排序" chatId:chatId];
            return;
        }

        // 同一会话同时只处理一条，避免并发回复
        @synchronized (self) {
            if (!g_inFlightChats) g_inFlightChats = [NSMutableSet set];
            if ([g_inFlightChats containsObject:chatId]) {
                NSLog(kAITweakLogPrefix "该会话正在回复中，忽略重复消息");
                return;
            }
            [g_inFlightChats addObject:chatId];
        }

        // 记录用户消息 → 带上下文请求 AI
        [[AIContext shared] appendUser:content chatId:chatId];
        NSArray *history = [[AIContext shared] messagesForChat:chatId];
        NSUInteger epoch = [[AIContext shared] epoch];

        NSUInteger replyEpoch = epoch;
        [[AIAPIClient shared] sendMessages:history
                              systemPrompt:kAISystemPrompt
                              styleProfile:[AISettings styleProfileForChat:chatId]
                                completion:^(NSString *reply, NSError *error) {
            @synchronized (self) {
                [g_inFlightChats removeObject:chatId];
            }
            // 清空后还在路上的回复直接丢弃，避免旧内容回流
            if ([[AIContext shared] epoch] != replyEpoch) {
                NSLog(kAITweakLogPrefix "上下文已清空，丢弃本次回复");
                return;
            }
            if (![self shouldReplyInChat:chatId]) {
                NSLog(kAITweakLogPrefix "开关已关闭，丢弃本次回复");
                return;
            }
            if (error) {
                NSLog(kAITweakLogPrefix "AI 请求失败: %@", error);
                // 错误信息只弹窗提示用户本人，绝不发给聊天对象
                [self presentAlertWithTitle:@"AI 回复失败"
                                    message:@"请求 DeepSeek 失败（网络异常、API Key 错误或余额不足），本次没有发送任何回复。请检查后重试。"];
                return;
            }
            [[AIContext shared] appendAssistant:reply chatId:chatId];
            [self sendReply:reply chatId:chatId];
        }];
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "trigger 模式处理异常: %@", exception);
    }
}

// 自动模式入口：消息先进上下文；已在回复中时，问题挂起等待补回，闲聊合并跳过
+ (void)enqueueReplyForChat:(NSString *)chatId message:(NSString *)content {
    @synchronized (self) {
        if (!g_inFlightChats) g_inFlightChats = [NSMutableSet set];
        if (!g_pendingChats) g_pendingChats = [NSMutableSet set];
        if ([g_inFlightChats containsObject:chatId]) {
            if ([self looksLikeQuestion:content]) {
                [g_pendingChats addObject:chatId];
            }
            return;
        }
    }
    [self startAutoReplyForChat:chatId];
}

// 粗略判断是否像提问（决定回复期间要不要补回）
+ (BOOL)looksLikeQuestion:(NSString *)text {
    if (text.length == 0) return NO;
    if ([text containsString:@"？"] || [text containsString:@"?"]) return YES;
    NSArray *keywords = @[@"吗", @"呢", @"么", @"什么", @"怎么", @"为啥", @"为什么",
                          @"哪个", @"哪家", @"谁", @"多少", @"几点", @"要不要",
                          @"能不能", @"行不行", @"可不可以", @"是不是"];
    for (NSString *keyword in keywords) {
        if ([text containsString:keyword]) return YES;
    }
    return NO;
}

+ (void)startAutoReplyForChat:(NSString *)chatId {
    @synchronized (self) {
        if (!g_inFlightChats) g_inFlightChats = [NSMutableSet set];
        if (!g_pendingChats) g_pendingChats = [NSMutableSet set];
        if ([g_inFlightChats containsObject:chatId]) return;
        [g_inFlightChats addObject:chatId];
        [g_pendingChats removeObject:chatId];
    }

    NSUInteger epoch = [[AIContext shared] epoch];
    double delay = [AISettings replyDelay];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSArray *history = [[AIContext shared] messagesForChat:chatId];
        NSUInteger replyEpoch = epoch;
        [[AIAPIClient shared] sendMessages:history
                              systemPrompt:[AISettings autoSystemPrompt]
                              styleProfile:[AISettings styleProfileForChat:chatId]
                                completion:^(NSString *reply, NSError *error) {
            @synchronized (self) {
                [g_inFlightChats removeObject:chatId];
            }
            // 清空后还在路上的回复直接丢弃
            if ([[AIContext shared] epoch] != replyEpoch) {
                NSLog(kAITweakLogPrefix "上下文已清空，丢弃本次自动回复");
                return;
            }
            if (![self shouldReplyInChat:chatId]) {
                NSLog(kAITweakLogPrefix "开关已关闭，丢弃本次自动回复");
                return;
            }
            if (error) {
                NSLog(kAITweakLogPrefix "自动回复失败: %@", error);
                // 错误信息绝不发给聊天对象，只在用户手机上弹窗
                [self presentAlertWithTitle:@"AI 自动回复失败"
                                    message:@"请求 DeepSeek 失败（网络异常或余额不足），本次没有发送任何回复。"];
                return;
            }
            // 模拟打字：按字数算时间（0.15 秒/字，0.8~8 秒）+ 0~1.5 秒随机波动
            double typing = MIN(MAX((double)reply.length * 0.15, 0.8), 8.0)
                          + (double)(arc4random_uniform(15) / 10.0);
            // 先记入上下文（发出后回显会被去重，不会记两遍）
            [[AIContext shared] appendAssistant:reply chatId:chatId];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(typing * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self sendReply:reply chatId:chatId];
                // 回复期间收到的问题：补回一条
                [self checkPendingForChat:chatId];
            });
        }];
    });
}

// 当前回复已发出，看看回复期间有没有挂起的问题
+ (void)checkPendingForChat:(NSString *)chatId {
    BOOL pending = NO;
    @synchronized (self) {
        if (g_pendingChats && [g_pendingChats containsObject:chatId]) {
            [g_pendingChats removeObject:chatId];
            pending = YES;
        }
    }
    if (pending) {
        if ([self shouldReplyInChat:chatId]) {
            NSLog(kAITweakLogPrefix "回复期间收到新问题，补回一条 (%@)", chatId);
            [self startAutoReplyForChat:chatId];
        } else {
            NSLog(kAITweakLogPrefix "开关已关闭，跳过补回 (%@)", chatId);
        }
    }
}

// 硬开关判断：全局 + 会话级都开着才允许回复
+ (BOOL)shouldReplyInChat:(NSString *)chatId {
    if (![AISettings enabled]) return NO;
    return [AISettings chatEnabled:chatId];
}

+ (NSString *)statusString {
    NSString *mode = isAutoMode() ? @"auto（自动代替聊天）" : @"trigger（@AI 触发）";

    NSString *activeKey = [AISettings apiKey];
    NSString *keyMasked = @"未填/过短";
    if (activeKey.length >= 10) {
        keyMasked = [NSString stringWithFormat:@"%@…%@（%lu位）",
                     [activeKey substringToIndex:6],
                     [activeKey substringFromIndex:activeKey.length - 4],
                     (unsigned long)activeKey.length];
    }

    NSString *whiteRaw = [kAIAllowedChats stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *whiteDesc = whiteRaw.length == 0 ? @"全部会话" : whiteRaw;

    return [NSString stringWithFormat:
        @"🤖 微信 AI v%@\n总开关：%@\n模式：%@\n模型：%@\n延迟：%.1f秒\nhook：收消息Async %@ / 收消息Ext %@ / 发送 %@\nwcplugins：%@\nAPI Key：%@\n白名单：%@\n风格档案：%ld 个好友",
        kAITweakVersion, [AISettings enabled] ? @"开" : @"关",
        mode, [AISettings model],
        [AISettings replyDelay],
        g_hookAsync ? @"✓" : @"✗",
        g_hookExt ? @"✓" : @"✗",
        g_hookSend ? @"✓" : @"✗",
        g_wcpluginsClassFound ? (g_wcpluginsRegistered ? (g_wcpluginsControllerRegistered ? @"wcplugins ✓ 设置页已注册" : @"wcplugins ✓ 开关已注册") : @"wcplugins ✗ 未注册成功") : @"未装 wcplugins",
        keyMasked, whiteDesc, (long)[AISettings styleProfileCount]];
}

+ (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = tweakTopViewController();
        if (!top) {
            NSLog(kAITweakLogPrefix "找不到窗口，无法弹窗");
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                      message:message
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)sendReply:(NSString *)text chatId:(NSString *)chatId {
    if (text.length == 0 || chatId.length == 0) return;

    void (^send)(void) = ^{
        CMessageMgr *mgr = wechatMessageMgr();
        if (!mgr) {
            NSLog(kAITweakLogPrefix "获取 CMessageMgr 失败");
            return;
        }
        // 标记最近回复，回显去重用（必须在调用发送接口前标记，防止同步回显先到）
        [self noteReplySent:text chatId:chatId];
        // 尝试多种发送接口：SendTextMessage → AddMsg:MsgWrap:（8.0.55 主路径）→ SendMessage:isSendByWeChat:
        BOOL sent = NO;

        if ([mgr respondsToSelector:@selector(SendTextMessage:toUsrName:)]) {
            [mgr SendTextMessage:text toUsrName:chatId];
            sent = YES;
        } else if ([mgr respondsToSelector:@selector(AddMsg:MsgWrap:)]) {
            // 8.0.5x 的发送接口：构造 CMessageWrap 后 AddMsg
            Class wrapCls = NSClassFromString(@"CMessageWrap");
            if (wrapCls) {
                NSString *selfUsr = wechatSelfUsrName();
                CMessageWrap *wrap = nil;
                if (selfUsr.length > 0) {
                    wrap = [[wrapCls alloc] initWithMsgType:1 nsFromUsr:selfUsr];
                } else {
                    wrap = [[wrapCls alloc] initWithMsgType:1];
                }
                if (wrap) {
                    [wrap setM_nsContent:text];
                    [wrap setM_nsToUsr:chatId];
                    [wrap setM_uiMessageType:1];
                    [wrap setM_uiCreateTime:(unsigned int)time(NULL)];
                    [wrap setM_uiStatus:1];
                    [mgr AddMsg:chatId MsgWrap:wrap];
                    sent = YES;
                }
            }
        } else {
            // 构造一个文本消息对象，走新版发送接口
            CMessageWrap *wrap = [[NSClassFromString(@"CMessageWrap") alloc] init];
            if (wrap) {
                [wrap setM_nsContent:text];
                [wrap setM_nsToUsr:chatId];
                [wrap setM_uiMessageType:1];

                id service = mgr;
                Class serviceCls = NSClassFromString(@"WCMessageService");
                Class centerCls = NSClassFromString(@"MMServiceCenter");
                id center = centerCls ? [(id)centerCls defaultCenter] : nil;
                if (serviceCls && center) {
                    id s = [center getService:serviceCls];
                    if (s) service = s;
                }
                if ([service respondsToSelector:@selector(SendMessage:isSendByWeChat:)]) {
                    [service SendMessage:wrap isSendByWeChat:YES];
                    sent = YES;
                }
            }
        }

        if (sent) {
            NSLog(kAITweakLogPrefix "已发送回复到 %@", chatId);
        } else {
            NSLog(kAITweakLogPrefix "所有发送接口都不支持，回复发送失败 (chat: %@)", chatId);
            [self presentAlertWithTitle:@"发送失败"
                                message:@"当前微信版本没有可用的发送接口，需要适配（请把微信版本号告诉作者）"];
        }
    };

    if ([NSThread isMainThread]) {
        send();
    } else {
        dispatch_async(dispatch_get_main_queue(), send);
    }
}

// 聊天信息页“AI 助手”开关被拨动
+ (void)aiSwitchChanged:(UISwitch *)sender {
    NSString *chatId = objc_getAssociatedObject(sender, &kAISwitchChatKey);
    if (chatId.length > 0) {
        [AISettings setChatEnabled:sender.on chatId:chatId];
        NSLog(kAITweakLogPrefix "会话开关：%@ -> %@", chatId, sender.on ? @"开" : @"关");
    }
}

// 聊天信息页“清空记忆”：确认后清空本会话上下文
+ (void)confirmClearMemoryForChat:(NSString *)chatId {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = tweakTopViewController();
        if (!top) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空本会话记忆"
                                                                       message:@"AI 将忘记这个会话之前的聊天内容，且无法恢复。确定清空？"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"清空"
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(UIAlertAction *action) {
            [[AIContext shared] clearChat:chatId];
            [self presentAlertWithTitle:@"已清空"
                                message:@"本会话的记忆已清空，AI 从现在开始重新了解上下文。"];
        }]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

// 聊天信息页“学习聊天风格”：确认后拉取最近记录 → DeepSeek 总结 → 存成本地档案
+ (void)confirmLearnStyleForChat:(NSString *)chatId {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = tweakTopViewController();
        if (!top) return;

        NSString *profile = [AISettings styleProfileForChat:chatId];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"学习聊天风格"
                                                                       message:profile.length > 0
            ? @"这个好友已有学习档案。可以重新学习覆盖，或清除档案。"
            : @"将读取这个好友最近 100 条文字聊天记录，并发送给 DeepSeek 总结你的说话风格（仅对这位好友生效）。\n\n记录只用于本次学习，原文不会保存，只保存风格总结。确定继续？"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:profile.length > 0 ? @"重新学习" : @"开始学习"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self learnStyleForChat:chatId];
        }]];
        if (profile.length > 0) {
            [alert addAction:[UIAlertAction actionWithTitle:@"清除档案"
                                                     style:UIAlertActionStyleDestructive
                                                   handler:^(UIAlertAction *action) {
                [AISettings clearStyleProfileForChat:chatId];
                [self presentAlertWithTitle:@"已清除"
                                    message:@"这个好友的风格档案已删除，回复恢复默认风格。"];
            }]];
        }
        [top presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)learnStyleForChat:(NSString *)chatId {
    NSArray *texts = fetchRecentTexts(chatId, 100);
    if (texts.count < 5) {
        [self presentAlertWithTitle:@"记录太少"
                            message:[NSString stringWithFormat:@"最近 100 条文字消息里只找到 %lu 条可用的（至少需要 5 条才能学习）。可以稍后再试，或直接在设置页粘贴聊天记录。", (unsigned long)texts.count]];
        return;
    }

    NSString *joined = [texts componentsJoinedByString:@"\n"];
    NSString *learnPrompt = @"你是一名聊天风格分析师。以下是某微信用户与其好友最近的聊天记录片段（包含用户本人的消息和对方的消息，可能不按时间顺序）。请总结这位“用户本人”的说话风格：语气、常用词/口头禅、句子长短、是否爱用表情和标点、回复习惯、惯用开场或结束语。用 150~250 字的中文直接输出总结，不要客套，不要写“分析如下”之类的开头。";
    NSArray *messages = @[@{@"role": @"user", @"content": joined}];

    [[AIAPIClient shared] sendMessages:messages
                          systemPrompt:learnPrompt
                          styleProfile:nil
                            completion:^(NSString *reply, NSError *error) {
        if (error) {
            NSLog(kAITweakLogPrefix "学习风格失败: %@", error);
            [self presentAlertWithTitle:@"学习失败"
                                message:@"调用 DeepSeek 失败（网络异常、API Key 错误或余额不足），请稍后重试。"];
            return;
        }
        NSString *profile = [reply stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [AISettings setStyleProfile:profile forChat:chatId];
        NSLog(kAITweakLogPrefix "风格学习完成（%lu 条记录）: %@", (unsigned long)texts.count, chatId);
        [self presentAlertWithTitle:@"学习完成"
                            message:[NSString stringWithFormat:
                                @"已保存这个好友的风格档案，之后与 ta 的对话会用你的语气回复。\n\n档案摘要：\n%@",
                                profile.length > 200 ? [profile substringToIndex:200] : profile]];
    }];
}

@end

#pragma mark - Hook 安装

static void (*orig_AsyncOnAddMsg)(id, SEL, id, CMessageWrap *);
static void (*orig_MainThreadNotifyToExt)(id, SEL, NSDictionary *);
static void (*orig_SendTextMessage)(id, SEL, NSString *, NSString *);

static void swz_AsyncOnAddMsg(id self, SEL _cmd, id arg1, CMessageWrap *wrap) {
    if (orig_AsyncOnAddMsg) {
        orig_AsyncOnAddMsg(self, _cmd, arg1, wrap);
    }
    [WeChatAIHandler handleIncomingMessage:wrap];
}

static void swz_MainThreadNotifyToExt(id self, SEL _cmd, NSDictionary *ext) {
    if (orig_MainThreadNotifyToExt) {
        orig_MainThreadNotifyToExt(self, _cmd, ext);
    }
    @try {
        if (![ext isKindOfClass:[NSDictionary class]]) return;
        CMessageWrap *wrap = ext[@"3"];
        if ([wrap isKindOfClass:NSClassFromString(@"CMessageWrap")]) {
            [WeChatAIHandler handleIncomingMessage:wrap];
        }
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "MainThreadNotifyToExt 处理异常: %@", exception);
    }
}

static void swz_SendTextMessage(id self, SEL _cmd, NSString *content, NSString *usrName) {
    if (orig_SendTextMessage) {
        orig_SendTextMessage(self, _cmd, content, usrName);
    }
}

// ============================================================
//  聊天信息页插入“AI 助手”开关行（8.0.55 适配）
//  dataSource 是 MMTableViewInfo，直接在表格数据源层面插行
// ============================================================

// 读取该页面的配置：VC、是否群聊、chatId、插入位置
static NSDictionary *aiBuildConfigForVC(UIViewController *vc, UITableView *tableView) {
    NSString *className = NSStringFromClass([vc class]);
    BOOL isGroup = [className containsString:@"ChatRoomInfo"];

    NSString *chatId = @"";
    NSString *ivarName = isGroup ? @"m_chatRoomContact" : @"m_contact";
    Ivar contactIvar = class_getInstanceVariable([vc class], [ivarName UTF8String]);
    if (contactIvar) {
        id contact = object_getIvar(vc, contactIvar);
        if ([contact respondsToSelector:@selector(m_nsUsrName)]) {
            chatId = [contact m_nsUsrName] ?: @"";
        }
    }

    // 动态找“查找聊天内容 / 备注”所在行，插在它下面
    NSInteger insertRow = isGroup ? 5 : 1;
    @try {
        NSString *anchor = isGroup ? @"备注" : @"查找聊天内容";
        NSInteger rows = [tableView numberOfRowsInSection:1];
        for (NSInteger row = 0; row < rows; row++) {
            UITableViewCell *cell = [tableView.dataSource tableView:tableView
                                               cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]];
            if ([[cell textLabel].text containsString:anchor]) {
                insertRow = row + 1;
                break;
            }
        }
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "定位插入行失败，用默认位置: %@", exception);
    }

    return @{@"vc": vc, @"group": @(isGroup), @"row": @(insertRow), @"chat": chatId};
}

static BOOL g_buildingConfig = NO;

// 取表格配置；没有就懒加载：沿响应链找到页面 VC 并挂上（不依赖 reloadTableData 时机）
static NSDictionary *aiConfigForTable(UITableView *tableView) {
    NSDictionary *config = objc_getAssociatedObject(tableView, &kAIConfigKey);
    if (config) return config;
    if (g_buildingConfig) return nil; // 防止扫描时递归

    g_buildingConfig = YES;
    @try {
        UIResponder *responder = tableView;
        while ((responder = [responder nextResponder])) {
            if ([responder isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)responder;
                NSString *className = NSStringFromClass([vc class]);
                if ([className isEqualToString:@"AddContactToChatRoomViewController"] ||
                    [className isEqualToString:@"ChatRoomInfoViewController"]) {
                    config = aiBuildConfigForVC(vc, tableView);
                    if (config) {
                        objc_setAssociatedObject(tableView, &kAIConfigKey, config,
                                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                }
                break;
            }
        }
    } @catch (NSException *exception) {
        config = nil;
    }
    g_buildingConfig = NO;
    return config;
}

// 用微信的 MMTableViewCell 创建开关行，样式尽量贴近原生
static UITableViewCell *aiMakeSwitchCell(BOOL on, NSString *chatId) {
    UITableViewCell *cell = nil;
    @try {
        Class cellClass = NSClassFromString(@"MMTableViewCell");
        cell = [[cellClass alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"WeChatAICell"];
    } @catch (NSException *exception) {
        cell = nil;
    }
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"WeChatAICell"];
    }
    cell.textLabel.text = @"AI 助手";
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.backgroundColor = [UIColor whiteColor];
    cell.contentView.backgroundColor = [UIColor whiteColor];
    UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
    switchView.on = on;
    objc_setAssociatedObject(switchView, &kAISwitchChatKey, chatId, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [switchView addTarget:[WeChatAIHandler class]
                   action:@selector(aiSwitchChanged:)
         forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = switchView;
    return cell;
}

// 用微信的 MMTableViewCell 创建“清空记忆”行
static UITableViewCell *aiMakeMemoryCell(void) {
    UITableViewCell *cell = nil;
    @try {
        Class cellClass = NSClassFromString(@"MMTableViewCell");
        cell = [[cellClass alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"WeChatAIMemoryCell"];
    } @catch (NSException *exception) {
        cell = nil;
    }
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"WeChatAIMemoryCell"];
    }
    cell.textLabel.text = @"清空记忆";
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.textLabel.textColor = [UIColor systemRedColor];
    cell.backgroundColor = [UIColor whiteColor];
    cell.contentView.backgroundColor = [UIColor whiteColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

// 用微信的 MMTableViewCell 创建“学习聊天风格”行
static UITableViewCell *aiMakeLearnCell(void) {
    UITableViewCell *cell = nil;
    @try {
        Class cellClass = NSClassFromString(@"MMTableViewCell");
        cell = [[cellClass alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"WeChatAILearnCell"];
    } @catch (NSException *exception) {
        cell = nil;
    }
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"WeChatAILearnCell"];
    }
    cell.textLabel.text = @"学习聊天风格";
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.backgroundColor = [UIColor whiteColor];
    cell.contentView.backgroundColor = [UIColor whiteColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

static void (*orig_reloadTableData_addContact)(id, SEL);
static void (*orig_reloadTableData_chatRoom)(id, SEL);
static void (*orig_viewDidLoad_addContact)(id, SEL);
static void (*orig_viewDidLoad_chatRoom)(id, SEL);
static void (*orig_viewDidAppear_addContact)(id, SEL, BOOL);
static void (*orig_viewDidAppear_chatRoom)(id, SEL, BOOL);

// 直接从页面 VC 的 m_tableView 取表格并挂配置（不依赖响应链，老日志确认这条 ivar 路径可用）
static void attachChatInfoConfigForVC(UIViewController *vc, NSString *className) {
    @try {
        UITableView *tableView = nil;
        Ivar tableIvar = class_getInstanceVariable([vc class], "m_tableView");
        if (tableIvar) tableView = object_getIvar(vc, tableIvar);
        if (!tableView) tableView = [AIDiagnostics findTableViewInView:vc.view];
        if (!tableView) return;
        objc_setAssociatedObject(tableView, &kAIConfigKey,
                                 aiBuildConfigForVC(vc, tableView),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // 重新加载让 AI 助手/清空记忆立即出现
        if ([NSThread isMainThread]) {
            [tableView reloadData];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [tableView reloadData];
            });
        }
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "挂聊天信息页配置失败: %@", exception);
    }
}

static void swz_viewDidLoad(id self, SEL _cmd) {
    NSString *className = NSStringFromClass([self class]);
    if ([className isEqualToString:@"AddContactToChatRoomViewController"]) {
        if (orig_viewDidLoad_addContact) orig_viewDidLoad_addContact(self, _cmd);
    } else if ([className isEqualToString:@"ChatRoomInfoViewController"]) {
        if (orig_viewDidLoad_chatRoom) orig_viewDidLoad_chatRoom(self, _cmd);
    }
    if ([self isKindOfClass:[UIViewController class]]) {
        attachChatInfoConfigForVC((UIViewController *)self, className);
    }
}

static void swz_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    NSString *className = NSStringFromClass([self class]);
    if ([className isEqualToString:@"AddContactToChatRoomViewController"]) {
        if (orig_viewDidAppear_addContact) orig_viewDidAppear_addContact(self, _cmd, animated);
    } else if ([className isEqualToString:@"ChatRoomInfoViewController"]) {
        if (orig_viewDidAppear_chatRoom) orig_viewDidAppear_chatRoom(self, _cmd, animated);
    }
    if ([self isKindOfClass:[UIViewController class]]) {
        attachChatInfoConfigForVC((UIViewController *)self, className);
    }
}

static void swz_reloadTableData(id self, SEL _cmd) {
    NSString *className = NSStringFromClass([self class]);
    if ([className isEqualToString:@"AddContactToChatRoomViewController"]) {
        if (orig_reloadTableData_addContact) orig_reloadTableData_addContact(self, _cmd);
    } else if ([className isEqualToString:@"ChatRoomInfoViewController"]) {
        if (orig_reloadTableData_chatRoom) orig_reloadTableData_chatRoom(self, _cmd);
    }

    @try {
        if (![self isKindOfClass:[UIViewController class]]) return;
        UIViewController *vc = (UIViewController *)self;
        UITableView *tableView = nil;
        Ivar tableIvar = class_getInstanceVariable([vc class], "m_tableView");
        if (tableIvar) tableView = object_getIvar(vc, tableIvar);
        if (!tableView) tableView = [AIDiagnostics findTableViewInView:vc.view];
        if (tableView) {
            objc_setAssociatedObject(tableView, &kAIConfigKey,
                                     aiBuildConfigForVC(vc, tableView),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "关联聊天信息页表格失败: %@", exception);
    }
}

// ---- MMTableViewInfo 数据源方法（含父类实现，靠关联判断只影响这两个页面）----

static NSInteger (*orig_mm_numberOfRows)(id, SEL, UITableView *, NSInteger);
static void *kNumberRowsHookedKey = &kNumberRowsHookedKey;  // dataSource 类已挂钩标记
static void *kOrigNumberRowsKey = &kOrigNumberRowsKey;      // 每个类自己的原实现
static NSInteger swz_mm_numberOfRows(id self, SEL _cmd, UITableView *tableView, NSInteger section) {
    // 优先用“当前 dataSource 类”自己的原实现（子类可能覆写了行数方法）
    NSInteger (*origFn)(id, SEL, UITableView *, NSInteger) = orig_mm_numberOfRows;
    NSValue *classOrig = objc_getAssociatedObject(object_getClass(self), &kOrigNumberRowsKey);
    if (classOrig) origFn = (NSInteger (*)(id, SEL, UITableView *, NSInteger))[classOrig pointerValue];
    NSInteger orig = origFn ? origFn(self, _cmd, tableView, section) : 0;
    NSDictionary *config = aiConfigForTable(tableView);
    if (config && section == 1) {
        return orig + 3; // AI 助手开关 + 清空记忆 + 学习聊天风格
    }
    return orig;
}

// 自愈：如果表格的 dataSource 是 MMTableViewInfo 子类且覆写了行数方法，
// 基类 hook 管不到它，这里把这个类也 hook 上（只影响带我们配置的表格）。
// 返回 YES 表示“刚刚补挂”，调用方需要刷一次表格让新行数生效
static BOOL ensureNumberRowsHookedForTable(UITableView *tableView) {
    if (!tableView.dataSource) return NO;
    Class ds = object_getClass(tableView.dataSource);
    if (!ds) return NO;
    if (objc_getAssociatedObject(ds, &kNumberRowsHookedKey)) return NO;
    Method method = class_getInstanceMethod(ds, @selector(tableView:numberOfRowsInSection:));
    if (!method) return NO;
    IMP imp = method_getImplementation(method);
    if (imp == (IMP)swz_mm_numberOfRows) {
        // 已经是我们的实现（继承自已 hook 的父类），只需标记，避免重复包装
        objc_setAssociatedObject(ds, &kNumberRowsHookedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return NO;
    }
    objc_setAssociatedObject(ds, &kOrigNumberRowsKey,
                             [NSValue valueWithPointer:imp], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(ds, &kNumberRowsHookedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    method_setImplementation(method, (IMP)swz_mm_numberOfRows);
    return YES;
}

static UITableViewCell *(*orig_mm_cellForRow)(id, SEL, UITableView *, NSIndexPath *);
static UITableViewCell *swz_mm_cellForRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    if (ensureNumberRowsHookedForTable(tableView)) {
        // 刚补挂行数扩展：这轮布局已经算完，主动刷一次让“清空记忆”立刻出现
        dispatch_async(dispatch_get_main_queue(), ^{
            [tableView reloadData];
        });
    }
    NSDictionary *config = aiConfigForTable(tableView);
    if (config && indexPath.section == 1) {
        NSInteger insertRow = [config[@"row"] integerValue];
        if (indexPath.row == insertRow) {
            BOOL on = [AISettings chatEnabled:config[@"chat"]];
            return aiMakeSwitchCell(on, config[@"chat"]);
        }
        if (indexPath.row == insertRow + 1) {
            return aiMakeMemoryCell();
        }
        if (indexPath.row == insertRow + 2) {
            return aiMakeLearnCell();
        }
        if (indexPath.row > insertRow + 2) {
            NSIndexPath *shifted = [NSIndexPath indexPathForRow:indexPath.row - 3 inSection:indexPath.section];
            return orig_mm_cellForRow ? orig_mm_cellForRow(self, _cmd, tableView, shifted) : nil;
        }
    }
    return orig_mm_cellForRow ? orig_mm_cellForRow(self, _cmd, tableView, indexPath) : nil;
}

static void (*orig_mm_didSelect)(id, SEL, UITableView *, NSIndexPath *);
static void swz_mm_didSelect(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    ensureNumberRowsHookedForTable(tableView);
    NSDictionary *config = aiConfigForTable(tableView);
    if (config && indexPath.section == 1) {
        NSInteger insertRow = [config[@"row"] integerValue];
        if (indexPath.row == insertRow) {
            NSString *chatId = config[@"chat"];
            BOOL nowOn = [AISettings chatEnabled:chatId];
            [AISettings setChatEnabled:!nowOn chatId:chatId];
            [tableView reloadData];
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            return;
        }
        if (indexPath.row == insertRow + 1) {
            [WeChatAIHandler confirmClearMemoryForChat:config[@"chat"]];
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            return;
        }
        if (indexPath.row == insertRow + 2) {
            [WeChatAIHandler confirmLearnStyleForChat:config[@"chat"]];
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            return;
        }
        if (indexPath.row > insertRow + 2) {
            NSIndexPath *shifted = [NSIndexPath indexPathForRow:indexPath.row - 3 inSection:indexPath.section];
            if (orig_mm_didSelect) orig_mm_didSelect(self, _cmd, tableView, shifted);
            return;
        }
    }
    if (orig_mm_didSelect) orig_mm_didSelect(self, _cmd, tableView, indexPath);
}

static CGFloat (*orig_mm_heightForRow)(id, SEL, UITableView *, NSIndexPath *);
static CGFloat swz_mm_heightForRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    ensureNumberRowsHookedForTable(tableView);
    NSDictionary *config = aiConfigForTable(tableView);
    if (config && indexPath.section == 1) {
        NSInteger insertRow = [config[@"row"] integerValue];
        if (indexPath.row == insertRow) return 44;
        if (indexPath.row == insertRow + 1) return 44;
        if (indexPath.row == insertRow + 2) return 44;
        if (indexPath.row > insertRow + 2) {
            NSIndexPath *shifted = [NSIndexPath indexPathForRow:indexPath.row - 3 inSection:indexPath.section];
            return orig_mm_heightForRow ? orig_mm_heightForRow(self, _cmd, tableView, shifted) : 44;
        }
    }
    return orig_mm_heightForRow ? orig_mm_heightForRow(self, _cmd, tableView, indexPath) : 44;
}

static void installChatInfoRowHooks(void) {
    Class addContactCls = NSClassFromString(@"AddContactToChatRoomViewController");
    Class chatRoomCls = NSClassFromString(@"ChatRoomInfoViewController");
    Class infoCls = NSClassFromString(@"MMTableViewInfo");
    if (!infoCls) return;

    Method method;
    // 只 hook“类自己实现”的方法，避免误改父类实现影响微信其他页面
    BOOL (^classDefines)(Class, SEL) = ^BOOL(Class cls, SEL sel) {
        if (!cls || !sel) return NO;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        BOOL found = NO;
        for (unsigned int i = 0; i < count; i++) {
            if (method_getName(methods[i]) == sel) {
                found = YES;
                break;
            }
        }
        free(methods);
        return found;
    };

    if (addContactCls) {
        if (classDefines(addContactCls, @selector(reloadTableData))) {
            method = class_getInstanceMethod(addContactCls, @selector(reloadTableData));
            orig_reloadTableData_addContact = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)swz_reloadTableData);
        }
        if (classDefines(addContactCls, @selector(viewDidLoad))) {
            method = class_getInstanceMethod(addContactCls, @selector(viewDidLoad));
            orig_viewDidLoad_addContact = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)swz_viewDidLoad);
        }
        if (classDefines(addContactCls, @selector(viewDidAppear:))) {
            method = class_getInstanceMethod(addContactCls, @selector(viewDidAppear:));
            orig_viewDidAppear_addContact = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)swz_viewDidAppear);
        }
    }
    if (chatRoomCls) {
        if (classDefines(chatRoomCls, @selector(reloadTableData))) {
            method = class_getInstanceMethod(chatRoomCls, @selector(reloadTableData));
            orig_reloadTableData_chatRoom = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)swz_reloadTableData);
        }
        if (classDefines(chatRoomCls, @selector(viewDidLoad))) {
            method = class_getInstanceMethod(chatRoomCls, @selector(viewDidLoad));
            orig_viewDidLoad_chatRoom = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)swz_viewDidLoad);
        }
        if (classDefines(chatRoomCls, @selector(viewDidAppear:))) {
            method = class_getInstanceMethod(chatRoomCls, @selector(viewDidAppear:));
            orig_viewDidAppear_chatRoom = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)swz_viewDidAppear);
        }
    }

    method = class_getInstanceMethod(infoCls, @selector(tableView:numberOfRowsInSection:));
    if (method) {
        orig_mm_numberOfRows = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)swz_mm_numberOfRows);
    }
    method = class_getInstanceMethod(infoCls, @selector(tableView:cellForRowAtIndexPath:));
    if (method) {
        orig_mm_cellForRow = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)swz_mm_cellForRow);
    }
    method = class_getInstanceMethod(infoCls, @selector(tableView:didSelectRowAtIndexPath:));
    if (method) {
        orig_mm_didSelect = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)swz_mm_didSelect);
    }
    method = class_getInstanceMethod(infoCls, @selector(tableView:heightForRowAtIndexPath:));
    if (method) {
        orig_mm_heightForRow = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)swz_mm_heightForRow);
    }

    NSLog(kAITweakLogPrefix "聊天信息页 AI 开关行 hook 安装完成");
}

static BOOL g_hooksInstalled = NO;

// 返回 0 表示类还没加载、稍后重试；返回 1 表示已处理（无论成功失败都不再重试）
static int installHooks(void) {
    if (g_hooksInstalled) return 1;

    Class cls = NSClassFromString(@"CMessageMgr");
    if (!cls) return 0;

    g_hooksInstalled = YES;

    Method recvMethod = class_getInstanceMethod(cls, @selector(AsyncOnAddMsg:MsgWrap:));
    if (recvMethod) {
        orig_AsyncOnAddMsg = (void *)method_getImplementation(recvMethod);
        method_setImplementation(recvMethod, (IMP)swz_AsyncOnAddMsg);
        g_hookAsync = YES;
        NSLog(kAITweakLogPrefix "hook 安装成功: AsyncOnAddMsg:MsgWrap:");

        // 首次加载弹一次提示，方便确认注入是否成功
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSString *shownVersion = [defaults stringForKey:@"WeChatAIWelcomeVersion"];
            if ([shownVersion isEqualToString:kAITweakVersion]) return;
            [defaults setObject:kAITweakVersion forKey:@"WeChatAIWelcomeVersion"];
            [defaults synchronize];

            UIViewController *top = tweakTopViewController();
            if (!top) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"微信 AI 助手已加载"
                message:[NSString stringWithFormat:@"v%@ 已加载\n默认全部会话的 AI 均为关闭，在聊天信息页打开“AI 助手”后，该会话才会自动回复。\n设置入口：我的 → 插件页面 → 微信 AI 助手", kAITweakVersion]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [top presentViewController:alert animated:YES completion:nil];
        });
    } else {
        NSLog(kAITweakLogPrefix "没有找到 AsyncOnAddMsg:MsgWrap:，当前微信版本可能改了接口");
    }

    // 新版微信的收消息路径（8.x 起消息从这里通知出来）
    Method extMethod = class_getInstanceMethod(cls, @selector(MainThreadNotifyToExt:));
    if (extMethod) {
        orig_MainThreadNotifyToExt = (void *)method_getImplementation(extMethod);
        method_setImplementation(extMethod, (IMP)swz_MainThreadNotifyToExt);
        g_hookExt = YES;
        NSLog(kAITweakLogPrefix "hook 安装成功: MainThreadNotifyToExt:");
    } else {
        NSLog(kAITweakLogPrefix "没有找到 MainThreadNotifyToExt:，只走 AsyncOnAddMsg 收消息");
    }

    Method sendMethod = class_getInstanceMethod(cls, @selector(SendTextMessage:toUsrName:));
    if (sendMethod) {
        orig_SendTextMessage = (void *)method_getImplementation(sendMethod);
        method_setImplementation(sendMethod, (IMP)swz_SendTextMessage);
        g_hookSend = YES;
        NSLog(kAITweakLogPrefix "hook 安装成功: SendTextMessage:toUsrName:");
    } else {
        NSLog(kAITweakLogPrefix "没有找到 SendTextMessage:toUsrName:，本机发送记录将不可用");
    }

    // 聊天信息页插入“AI 助手”开关行
    installChatInfoRowHooks();
    return 1;
}

static void retryInstall(int remaining) {
    if (installHooks()) return;
    if (remaining <= 0) {
        NSLog(kAITweakLogPrefix "重试结束，仍未等到 CMessageMgr 加载");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        retryInstall(remaining - 1);
    });
}

// 注册到 wcplugins 插件管理：让“我的 → 插件页面”出现我们的开关
static void registerWithWCPlugins(int remaining) {
    if (g_wcpluginsRegistered) return; // 幂等：只注册一次，避免重复条目
    Class mgrClass = NSClassFromString(@"WCPluginsMgr");
    if (mgrClass && [mgrClass respondsToSelector:@selector(sharedInstance)]) {
        g_wcpluginsClassFound = YES;
        id mgr = [mgrClass sharedInstance];
        if (mgr) {
            // 预置默认值，让 wcplugins 的开关状态和插件内置默认（开）保持一致
            [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"WeChatAIEnabled" : @YES}];
            // 优先：注册可点击条目，点进去就是 AI 设置页
            if ([mgr respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                [mgr registerControllerWithTitle:@"微信 AI 助手"
                                         version:kAITweakVersion
                                      controller:@"AIPromptEditorViewController"];
                g_wcpluginsControllerRegistered = YES;
                g_wcpluginsRegistered = YES;
                NSLog(kAITweakLogPrefix "已注册到 wcplugins（设置页条目）");
                return;
            }
            // 老版本 wcplugins：退化为单个开关
            if ([mgr respondsToSelector:@selector(registerSwitchWithTitle:key:)]) {
                [mgr registerSwitchWithTitle:@"微信 AI 助手" key:@"WeChatAIEnabled"];
                g_wcpluginsRegistered = YES;
                NSLog(kAITweakLogPrefix "已注册到 wcplugins（开关）");
                return;
            }
        }
    }
    if (g_wcpluginsRegistered || remaining <= 0) {
        NSLog(kAITweakLogPrefix "未找到 WCPluginsMgr，跳过 wcplugins 适配");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        registerWithWCPlugins(remaining - 1);
    });
}

__attribute__((constructor))
static void WeChatAIInit(void) {
    NSLog(kAITweakLogPrefix "插件已加载，等待微信初始化…");
    g_dedupLock = [[NSObject alloc] init];
    g_seenKeys = [NSMutableSet set];
    g_seenOrder = [NSMutableArray array];
    g_replyLock = [[NSObject alloc] init];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidFinishLaunchingNotification"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        retryInstall(10);
        registerWithWCPlugins(10);
    }];

    // 兜底：如果通知已经发过，直接靠延时重试
    retryInstall(10);
    registerWithWCPlugins(10);
}

// 辅助：递归查找 UITableView（仅聊天信息页插行用，无其他副作用）
@implementation AIDiagnostics

+ (UITableView *)findTableViewInView:(UIView *)view {
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *subview in view.subviews) {
        UITableView *found = [self findTableViewInView:subview];
        if (found) return found;
    }
    return nil;
}

@end
