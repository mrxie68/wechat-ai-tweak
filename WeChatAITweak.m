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
static BOOL g_sendingReply = NO;

+ (void)handleIncomingMessage:(CMessageWrap *)wrap {
    @try {
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
            if (![self handlePossibleCommand:content chatId:chatId] && isAutoMode()) {
                [[AIContext shared] appendAssistant:content chatId:chatId];
            }
            return;
        }

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
        [self maybeAutoReplyInChat:chatId];
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
            [[AIContext shared] clearChat:chatId];
            [self sendReply:@"✅ 上下文已清空" chatId:chatId];
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

        [[AIAPIClient shared] sendMessages:history
                              systemPrompt:kAISystemPrompt
                                completion:^(NSString *reply, NSError *error) {
            @synchronized (self) {
                [g_inFlightChats removeObject:chatId];
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

+ (void)maybeAutoReplyInChat:(NSString *)chatId {
    @synchronized (self) {
        if (!g_inFlightChats) g_inFlightChats = [NSMutableSet set];
        if ([g_inFlightChats containsObject:chatId]) {
            // 已有回复在生成中，消息仍会进上下文，但不重复发起请求
            return;
        }
        [g_inFlightChats addObject:chatId];
    }

    double delay = kAIReplyDelaySeconds;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSArray *history = [[AIContext shared] messagesForChat:chatId];
        [[AIAPIClient shared] sendMessages:history
                              systemPrompt:[AISettings autoSystemPrompt]
                                completion:^(NSString *reply, NSError *error) {
            @synchronized (self) {
                [g_inFlightChats removeObject:chatId];
            }
            if (error) {
                NSLog(kAITweakLogPrefix "自动回复失败: %@", error);
                [self sendReply:@"⚠️ AI 调用失败（请检查 API Key / 网络 / 余额）" chatId:chatId];
                return;
            }
            // 发送 hook 会把这条回复记进上下文
            [self sendReply:reply chatId:chatId];
        }];
    });
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
        [[AIContext shared] clearChat:chatId];
        [self sendReply:@"✅ 上下文已清空" chatId:chatId];
    } else if ([command isEqualToString:@"test"]) {
        // 本地链路测试：不调用 API。弹窗 = 收消息正常；消息回复 = 发送正常
        [self presentAlertWithTitle:@"链路测试"
                            message:@"✅ 已收到命令（收消息正常）\n如果同时收到一条“插件链路正常”的消息，说明发送也正常；只有弹窗没有消息，则是发送接口问题。"];
        [self sendReply:@"✅ 收到，插件链路正常（本地测试，未调用 API）" chatId:chatId];
    } else if ([command isEqualToString:@"status"]) {
        // 状态用弹窗展示，不依赖发送链路
        [self presentAlertWithTitle:@"微信 AI 状态" message:[self statusString]];
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
        @"🤖 微信 AI v%@\n模式：%@\n模型：%@\nhook：收消息Async %@ / 收消息Ext %@ / 发送 %@\nAPI Key：%@\n白名单：%@",
        kAITweakVersion, mode, [AISettings model],
        g_hookAsync ? @"✓" : @"✗",
        g_hookExt ? @"✓" : @"✗",
        g_hookSend ? @"✓" : @"✗",
        keyMasked, whiteDesc];
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
