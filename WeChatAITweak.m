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

// 界面诊断（临时功能）：识别聊天信息页类名
@interface AIDiagnostics : NSObject
+ (void)inspectViewController:(UIViewController *)viewController;
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
    CContact *selfContact = [contactMgr getSelfContact];
    NSString *usrName = [selfContact m_nsUsrName];
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
    return [kAIReplyMode isEqualToString:@"auto"];
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

// ===== 消息去重（新旧两条收消息 hook 同时安装，防止同一条消息处理两次）=====
static NSObject *g_dedupLock = nil;
static NSMutableSet *g_seenKeys = nil;
static NSMutableArray *g_seenOrder = nil;

static NSString *messageKey(CMessageWrap *wrap) {
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

#pragma mark - 核心逻辑

@interface WeChatAIHandler : NSObject
@end

@implementation WeChatAIHandler

static NSMutableSet *g_inFlightChats = nil;
static NSMutableSet *g_pendingChats = nil;
static BOOL g_sendingReply = NO;
static NSString *g_contextAccount = nil;
static void *kAIConfigKey = &kAIConfigKey;          // tableView -> 页面配置
static void *kAISwitchChatKey = &kAISwitchChatKey;  // 开关 -> chatId

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
        if ([wrap m_uiMessageType] != 1) return; // 1 = 文本消息

        NSString *content = [wrap m_nsContent];
        NSString *fromUsr = [wrap m_nsFromUsr];
        NSString *toUsr = [wrap m_nsToUsr];
        if (content.length == 0 || fromUsr.length == 0) return;

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

        // 自己发的消息：先识别 @AI 命令；不是命令则记进上下文（8.0.5x 没有发送 hook，靠回显记录）
        if (isSelf) {
            if ([self handlePossibleCommand:content chatId:chatId]) return;
            if ([AISettings enabled] && isAutoMode()) {
                [[AIContext shared] appendAssistant:content chatId:chatId];
            }
            return;
        }

        // 机器人总开关：关闭时别人的消息一律不处理（管理命令只对“自己发的”生效）
        if (![AISettings enabled]) return;

        // 会话级开关：单聊默认开，群聊默认关（防误回复）；可发 @AI 开 / @AI 关 切换
        BOOL defaultChatOn = isGroup ? NO : YES;
        if (![AISettings chatEnabled:chatId defaultEnabled:defaultChatOn]) return;

        BOOL autoMode = isAutoMode();

        // 自动模式下，群聊默认仍走 @AI 触发，避免误回复
        if (autoMode && isGroup && !kAIAutoReplyInGroups) {
            if ([content hasPrefix:kAITrigger]) {
                [self handleTriggerMessage:content chatId:chatId];
            }
            return;
        }

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

+ (void)handleTriggerMessage:(NSString *)content chatId:(NSString *)chatId {
    @try {
        NSString *question = [content substringFromIndex:kAITrigger.length];
        question = [question stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        // 命令：清空上下文
        if ([question isEqualToString:@"清空"] || [question isEqualToString:@"reset"]) {
            [[AIContext shared] clearAll];
            [self sendReply:@"✅ 已清空全部会话的上下文" chatId:chatId];
            return;
        }

        // 命令：打开微信内设置页（兜底路径：发送 hook 未生效时也能用）
        if ([question isEqualToString:@"设置"] || [question isEqualToString:@"settings"]) {
            [self handleCommand:@"settings" chatId:chatId];
            return;
        }

        // 本地命令：链路测试 / 状态（不调用 API）
        if ([question isEqualToString:@"测试"] || [question isEqualToString:@"test"]) {
            [self handleCommand:@"test" chatId:chatId];
            return;
        }
        if ([question isEqualToString:@"状态"] || [question isEqualToString:@"status"]) {
            [self handleCommand:@"status" chatId:chatId];
            return;
        }

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
                [self sendReply:@"🤖 AI 暂时开小差了，请稍后再试。" chatId:chatId];
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
                [self sendReply:@"⚠️ AI 调用失败（请检查 API Key / 网络 / 余额）" chatId:chatId];
                return;
            }
            // 模拟打字：按字数算时间（0.15 秒/字，0.8~8 秒）+ 0~1.5 秒随机波动
            double typing = MIN(MAX((double)reply.length * 0.15, 0.8), 8.0)
                          + (double)(arc4random_uniform(15) / 10.0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(typing * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                // 回复发出后，收消息回显会把它记进上下文
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
    BOOL isGroup = [chatId containsString:@"@chatroom"];
    return [AISettings chatEnabled:chatId defaultEnabled:!isGroup];
}

// 收消息链路里的命令兜底：自己发的 @AI 命令也识别；返回 YES 表示是命令
+ (BOOL)handlePossibleCommand:(NSString *)content chatId:(NSString *)chatId {
    NSString *command = [self commandFromContent:content];
    if (command) {
        [self handleCommand:command chatId:chatId];
        return YES;
    }
    return NO;
}

// 自己手动发送的命令：@AI 设置 / @AI 清空
+ (NSString *)commandFromContent:(NSString *)content {
    if (![content hasPrefix:kAITrigger]) return nil;
    NSString *question = [content substringFromIndex:kAITrigger.length];
    question = [question stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([question isEqualToString:@"设置"] || [question isEqualToString:@"settings"]) return @"settings";
    if ([question isEqualToString:@"清空"] || [question isEqualToString:@"reset"]) return @"clear";
    if ([question isEqualToString:@"测试"] || [question isEqualToString:@"test"]) return @"test";
    if ([question isEqualToString:@"状态"] || [question isEqualToString:@"status"]) return @"status";
    if ([question isEqualToString:@"开"] || [question isEqualToString:@"on"]) return @"chatOn";
    if ([question isEqualToString:@"关"] || [question isEqualToString:@"off"]) return @"chatOff";
    return nil;
}

+ (void)handleCommand:(NSString *)command chatId:(NSString *)chatId {
    if ([command isEqualToString:@"settings"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *top = tweakTopViewController();
            if (!top) {
                NSLog(kAITweakLogPrefix "找不到窗口，无法弹出设置页");
                return;
            }
            UINavigationController *nav = [[UINavigationController alloc]
                initWithRootViewController:[[AIPromptEditorViewController alloc] init]];
            [top presentViewController:nav animated:YES completion:nil];
        });
    } else if ([command isEqualToString:@"clear"]) {
        [[AIContext shared] clearAll];
        [self sendReply:@"✅ 已清空全部会话的上下文" chatId:chatId];
    } else if ([command isEqualToString:@"test"]) {
        // 本地链路测试：不调用 API。弹窗 = 收消息正常；消息回复 = 发送正常
        [self presentAlertWithTitle:@"链路测试"
                            message:@"✅ 已收到命令（收消息正常）\n如果同时收到一条“插件链路正常”的消息，说明发送也正常；只有弹窗没有消息，则是发送接口问题。"];
        [self sendReply:@"✅ 收到，插件链路正常（本地测试，未调用 API）" chatId:chatId];
    } else if ([command isEqualToString:@"status"]) {
        // 状态用弹窗展示，不依赖发送链路
        [self presentAlertWithTitle:@"微信 AI 状态" message:[self statusStringForChat:chatId]];
    } else if ([command isEqualToString:@"chatOn"]) {
        [AISettings setChatEnabled:YES chatId:chatId];
        [self sendReply:@"✅ 本会话 AI 已开启" chatId:chatId];
    } else if ([command isEqualToString:@"chatOff"]) {
        [AISettings setChatEnabled:NO chatId:chatId];
        [self sendReply:@"✅ 本会话 AI 已关闭" chatId:chatId];
    }
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
        @"🤖 微信 AI v%@\n开关：%@\n模式：%@\n模型：%@\n延迟：%.1f秒\nhook：收消息Async %@ / 收消息Ext %@ / 发送 %@\nAPI Key：%@\n白名单：%@",
        kAITweakVersion, [AISettings enabled] ? @"开" : @"关",
        mode, [AISettings model],
        [AISettings replyDelay],
        g_hookAsync ? @"✓" : @"✗",
        g_hookExt ? @"✓" : @"✗",
        g_hookSend ? @"✓" : @"✗",
        keyMasked, whiteDesc];
}

+ (NSString *)statusStringForChat:(NSString *)chatId {
    BOOL isGroup = [chatId containsString:@"@chatroom"];
    BOOL chatOn = [AISettings chatEnabled:chatId defaultEnabled:!isGroup];
    return [[self statusString] stringByAppendingFormat:@"\n本会话 AI：%@", chatOn ? @"开" : @"关"];
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
        // 尝试多种发送接口：SendTextMessage → AddMsg:MsgWrap:（8.0.55 主路径）→ SendMessage:isSendByWeChat:
        BOOL sent = NO;

        if ([mgr respondsToSelector:@selector(SendTextMessage:toUsrName:)]) {
            g_sendingReply = YES;
            [mgr SendTextMessage:text toUsrName:chatId];
            g_sendingReply = NO;
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
    @try {
        // 自己手动发的命令：拦截，不真正发送
        if (!g_sendingReply && content.length > 0 && usrName.length > 0 && isChatAllowed(usrName)) {
            NSString *command = [WeChatAIHandler commandFromContent:content];
            if (command) {
                NSLog(kAITweakLogPrefix "拦截命令 %@ (chat: %@)", command, usrName);
                [WeChatAIHandler handleCommand:command chatId:usrName];
                return;
            }
        }
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "命令处理异常: %@", exception);
    }

    if (orig_SendTextMessage) {
        orig_SendTextMessage(self, _cmd, content, usrName);
    }
}

// ---- 界面诊断（临时）：定位没出开关行的单聊页面 ----
static void (*orig_pushViewController)(id, SEL, UIViewController *, BOOL);
static void (*orig_presentViewController)(id, SEL, UIViewController *, BOOL, void (^)(void));

static void swz_pushViewController(id self, SEL _cmd, UIViewController *viewController, BOOL animated) {
    if (orig_pushViewController) {
        orig_pushViewController(self, _cmd, viewController, animated);
    }
    @try {
        [AIDiagnostics inspectViewController:viewController];
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "界面诊断异常: %@", exception);
    }
}

static void swz_presentViewController(id self, SEL _cmd, UIViewController *viewController, BOOL animated, void (^completion)(void)) {
    if (orig_presentViewController) {
        orig_presentViewController(self, _cmd, viewController, animated, completion);
    }
    @try {
        [AIDiagnostics inspectViewController:viewController];
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "界面诊断异常: %@", exception);
    }
}

// ============================================================
//  聊天信息页插入“AI 助手”开关行（8.0.55 适配）
//  dataSource 是 MMTableViewInfo，直接在表格数据源层面插行
// ============================================================

// 读取该页面的配置：VC、是否群聊、chatId、插入位置
static NSDictionary *aiBuildConfigForVC(UIViewController *vc, UITableView *tableView) {
    NSString *className = NSStringFromClass([vc class]);
    BOOL isGroup = [className isEqualToString:@"ChatRoomInfoViewController"];

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

static NSDictionary *aiConfigForTable(UITableView *tableView) {
    return objc_getAssociatedObject(tableView, &kAIConfigKey);
}

static void (*orig_reloadTableData_addContact)(id, SEL);
static void (*orig_reloadTableData_chatRoom)(id, SEL);

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
static NSInteger swz_mm_numberOfRows(id self, SEL _cmd, UITableView *tableView, NSInteger section) {
    NSInteger orig = orig_mm_numberOfRows ? orig_mm_numberOfRows(self, _cmd, tableView, section) : 0;
    NSDictionary *config = aiConfigForTable(tableView);
    if (config && section == 1) return orig + 1;
    return orig;
}

static UITableViewCell *(*orig_mm_cellForRow)(id, SEL, UITableView *, NSIndexPath *);
static UITableViewCell *swz_mm_cellForRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    NSDictionary *config = aiConfigForTable(tableView);
    if (config && indexPath.section == 1) {
        NSInteger insertRow = [config[@"row"] integerValue];
        if (indexPath.row == insertRow) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                           reuseIdentifier:@"WeChatAICell"];
            cell.textLabel.text = @"AI 助手";
            cell.textLabel.font = [UIFont systemFontOfSize:16];
            UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
            switchView.on = [AISettings chatEnabled:config[@"chat"]
                                    defaultEnabled:![config[@"group"] boolValue]];
            objc_setAssociatedObject(switchView, &kAISwitchChatKey, config[@"chat"],
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
            [switchView addTarget:[WeChatAIHandler class]
                           action:@selector(aiSwitchChanged:)
                 forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = switchView;
            return cell;
        }
        if (indexPath.row > insertRow) {
            NSIndexPath *shifted = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];
            return orig_mm_cellForRow ? orig_mm_cellForRow(self, _cmd, tableView, shifted) : nil;
        }
    }
    return orig_mm_cellForRow ? orig_mm_cellForRow(self, _cmd, tableView, indexPath) : nil;
}

static void (*orig_mm_didSelect)(id, SEL, UITableView *, NSIndexPath *);
static void swz_mm_didSelect(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    NSDictionary *config = aiConfigForTable(tableView);
    if (config && indexPath.section == 1) {
        NSInteger insertRow = [config[@"row"] integerValue];
        if (indexPath.row == insertRow) {
            NSString *chatId = config[@"chat"];
            BOOL isGroup = [config[@"group"] boolValue];
            BOOL nowOn = [AISettings chatEnabled:chatId defaultEnabled:!isGroup];
            [AISettings setChatEnabled:!nowOn chatId:chatId];
            [tableView reloadData];
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            return;
        }
        if (indexPath.row > insertRow) {
            NSIndexPath *shifted = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];
            if (orig_mm_didSelect) orig_mm_didSelect(self, _cmd, tableView, shifted);
            return;
        }
    }
    if (orig_mm_didSelect) orig_mm_didSelect(self, _cmd, tableView, indexPath);
}

static CGFloat (*orig_mm_heightForRow)(id, SEL, UITableView *, NSIndexPath *);
static CGFloat swz_mm_heightForRow(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    NSDictionary *config = aiConfigForTable(tableView);
    if (config && indexPath.section == 1) {
        NSInteger insertRow = [config[@"row"] integerValue];
        if (indexPath.row == insertRow) return 44;
        if (indexPath.row > insertRow) {
            NSIndexPath *shifted = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];
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
    if (addContactCls) {
        method = class_getInstanceMethod(addContactCls, @selector(reloadTableData));
        if (method) {
            orig_reloadTableData_addContact = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)swz_reloadTableData);
        }
    }
    if (chatRoomCls) {
        method = class_getInstanceMethod(chatRoomCls, @selector(reloadTableData));
        if (method) {
            orig_reloadTableData_chatRoom = (void *)method_getImplementation(method);
            method_setImplementation(method, (IMP)swz_reloadTableData);
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
                message:[NSString stringWithFormat:@"v%@ 已加载\n发 @AI 设置 配置提示词；发 @AI 状态 查看运行状态。", kAITweakVersion]
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

    // 界面诊断（临时）
    Method pushMethod = class_getInstanceMethod([UINavigationController class],
                                                @selector(pushViewController:animated:));
    if (pushMethod) {
        orig_pushViewController = (void *)method_getImplementation(pushMethod);
        method_setImplementation(pushMethod, (IMP)swz_pushViewController);
    }
    Method presentMethod = class_getInstanceMethod([UIViewController class],
                                                   @selector(presentViewController:animated:completion:));
    if (presentMethod) {
        orig_presentViewController = (void *)method_getImplementation(presentMethod);
        method_setImplementation(presentMethod, (IMP)swz_presentViewController);
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

__attribute__((constructor))
static void WeChatAIInit(void) {
    NSLog(kAITweakLogPrefix "插件已加载，等待微信初始化…");
    g_dedupLock = [[NSObject alloc] init];
    g_seenKeys = [NSMutableSet set];
    g_seenOrder = [NSMutableArray array];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidFinishLaunchingNotification"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        retryInstall(10);
    }];

    // 兜底：如果通知已经发过，直接靠延时重试
    retryInstall(10);
}

// ============================================================
//  界面诊断（临时）：打开聊天信息页时弹窗显示类名和插行条件
//  下一版会用真正的“AI 助手”菜单行替换掉它
// ============================================================
@implementation AIDiagnostics

+ (void)inspectViewController:(UIViewController *)viewController {
    if (!viewController) return;

    // 立即查一次；标题往往是页面加载后才设置的，0.6 秒后再查一次
    [self inspectOnce:viewController scanTable:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self inspectOnce:viewController scanTable:YES];
    });
}

+ (BOOL)looksLikeChatInfoPage:(NSString *)className title:(NSString *)title {
    if ([className containsString:@"ChatInfo"]
        || [className containsString:@"ChatDetail"]
        || [className containsString:@"ChatSetting"]
        || [className containsString:@"ChatRoomInfo"]
        || [className containsString:@"SessionDetail"]) {
        return YES;
    }
    if ([title containsString:@"聊天信息"]
        || [title containsString:@"聊天详情"]
        || [title containsString:@"群聊信息"]) {
        return YES;
    }
    return NO;
}

+ (void)inspectOnce:(UIViewController *)viewController scanTable:(BOOL)scanTable {
    NSString *className = NSStringFromClass([viewController class]);
    NSString *title = viewController.title ?: viewController.navigationItem.title ?: @"";
    if ([className isEqualToString:@"ChatRoomInfoViewController"]) return; // 群聊已生效，不再诊断

    BOOL matched = [self looksLikeChatInfoPage:className title:title];
    if (!matched && scanTable) {
        // 不猜类名：直接扫表格里有没有“查找聊天内容/备注”
        UITableView *scanTable = [self findTableViewForVC:viewController];
        if (scanTable && [self tableHasChatInfoAnchor:scanTable]) {
            matched = YES;
        }
    }
    if (!matched) return;

    // 每个类只提示一次，避免每次打开都弹
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *flagKey = [NSString stringWithFormat:@"WeChatAIDiagShown_%@_%@", kAITweakVersion, className];
    if ([defaults boolForKey:flagKey]) return;
    [defaults setBool:YES forKey:flagKey];

    NSString *detail = [NSString stringWithFormat:@"类名：%@\n标题：%@", className, title.length ? title : @"(空)"];

    // 导出表格结构：哪个 section 有“查找聊天内容/备注”，就能精确定位插行位置
    UITableView *tableView = nil;
    Ivar tableIvar = class_getInstanceVariable([viewController class], "m_tableView");
    if (tableIvar) {
        tableView = object_getIvar(viewController, tableIvar);
    }
    if (!tableView) {
        tableView = [self findTableViewInView:viewController.view];
    }
    if (tableView) {
        // 检查我们的插行配置有没有挂到这个表格上
        NSDictionary *config = objc_getAssociatedObject(tableView, &kAIConfigKey);
        detail = [detail stringByAppendingFormat:@"\n插行配置：%@", config ? @"已挂载" : @"未挂载"];
        detail = [detail stringByAppendingFormat:@"\n%@", [self dumpTable:tableView]];
        detail = [detail stringByAppendingFormat:@"\ndataSource: %@ / delegate: %@",
                  NSStringFromClass([tableView.dataSource class]),
                  NSStringFromClass([tableView.delegate class])];
    } else {
        detail = [detail stringByAppendingString:@"\n（未找到表格）"];
    }

    if (detail.length > 2400) {
        detail = [detail substringToIndex:2400];
        detail = [detail stringByAppendingString:@"\n…（过长截断）"];
    }

    // 自动复制到剪贴板，不用截图/OCR，直接粘贴发给我
    [[UIPasteboard generalPasteboard] setString:detail];
    detail = [detail stringByAppendingString:@"\n\n（内容已复制到剪贴板）"];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = tweakTopViewController();
        if (!top) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AI 表格结构"
                                                                      message:detail
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

+ (UITableView *)findTableViewForVC:(UIViewController *)viewController {
    UITableView *tableView = nil;
    Ivar tableIvar = class_getInstanceVariable([viewController class], "m_tableView");
    if (tableIvar) tableView = object_getIvar(viewController, tableIvar);
    if (!tableView) tableView = [self findTableViewInView:viewController.view];
    return tableView;
}

// 有界扫描：只在靠前的 section/行里找“查找聊天内容/备注”，避免大表格卡顿
+ (BOOL)tableHasChatInfoAnchor:(UITableView *)tableView {
    @try {
        NSInteger sections = MIN([tableView numberOfSections], 4);
        for (NSInteger section = 0; section < sections; section++) {
            NSInteger rows = MIN([tableView numberOfRowsInSection:section], 12);
            for (NSInteger row = 0; row < rows; row++) {
                UITableViewCell *cell = [tableView.dataSource tableView:tableView
                                                   cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
                NSString *labels = [self labelTextsInView:cell];
                if ([labels containsString:@"查找聊天内容"] || [labels containsString:@"备注"]) {
                    return YES;
                }
            }
        }
    } @catch (NSException *exception) {
        // 忽略，继续
    }
    return NO;
}

+ (UITableView *)findTableViewInView:(UIView *)view {
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *subview in view.subviews) {
        UITableView *found = [self findTableViewInView:subview];
        if (found) return found;
    }
    return nil;
}

+ (NSString *)dumpTable:(UITableView *)tableView {
    NSMutableString *result = [NSMutableString string];
    NSInteger sections = 0;
    @try {
        sections = [tableView numberOfSections];
    } @catch (NSException *e) {
        return @"（读取表格失败）";
    }
    [result appendFormat:@"sections=%ld\n", (long)sections];

    for (NSInteger section = 0; section < sections; section++) {
        NSInteger rows = 0;
        @try {
            rows = [tableView numberOfRowsInSection:section];
        } @catch (NSException *e) {
            continue;
        }
        [result appendFormat:@"[S%ld] rows=%ld\n", (long)section, (long)rows];

        NSInteger showRows = MIN(rows, 10);
        for (NSInteger row = 0; row < showRows; row++) {
            @try {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
                UITableViewCell *cell = [tableView.dataSource tableView:tableView cellForRowAtIndexPath:indexPath];
                [result appendFormat:@"  r%ld: %@\n", (long)row, [self labelTextsInView:cell]];
            } @catch (NSException *e) {
                [result appendFormat:@"  r%ld: （读取失败）\n", (long)row];
            }
        }
        if (rows > showRows) {
            [result appendFormat:@"  ...（共 %ld 行）\n", (long)rows];
        }
    }

    if (result.length > 900) {
        [result deleteCharactersInRange:NSMakeRange(900, result.length - 900)];
        [result appendString:@"\n…（内容过长已截断）"];
    }
    return result;
}

+ (NSString *)labelTextsInView:(UIView *)view {
    NSMutableArray *texts = [NSMutableArray array];
    [self collectLabelsInView:view into:texts];
    if (texts.count == 0) return NSStringFromClass([view class]);
    return [texts componentsJoinedByString:@" | "];
}

+ (NSString *)methodListOfClass:(Class)cls limit:(NSInteger)limit {
    if (!cls) return @"-";
    NSMutableArray *names = [NSMutableArray array];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count && names.count < limit; i++) {
        [names addObject:NSStringFromSelector(method_getName(methods[i]))];
    }
    free(methods);
    return [names componentsJoinedByString:@"\n"];
}

+ (void)collectLabelsInView:(UIView *)view into:(NSMutableArray *)texts {
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = ((UILabel *)view).text;
        if (text.length > 0 && texts.count < 4) {
            [texts addObject:text];
        }
    }
    for (UIView *subview in view.subviews) {
        [self collectLabelsInView:subview into:texts];
    }
}

@end
