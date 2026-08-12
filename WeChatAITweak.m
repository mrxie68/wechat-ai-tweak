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
@end

@interface CMessageMgr : NSObject
- (void)AsyncOnAddMsg:(id)arg1 MsgWrap:(CMessageWrap *)wrap;
- (void)SendTextMessage:(NSString *)content toUsrName:(NSString *)usrName;
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
    return [selfContact m_nsUsrName];
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

        // 自己发的消息不处理（本机发送由 SendTextMessage hook 记录上下文）
        NSString *selfUsr = wechatSelfUsrName();
        if (selfUsr.length > 0 && [fromUsr isEqualToString:selfUsr]) return;

        // 群聊会话 id 是 toUsr（@chatroom 结尾），单聊用 fromUsr
        BOOL isGroup = [toUsr containsString:@"@chatroom"];
        NSString *chatId = isGroup ? toUsr : fromUsr;

        // 白名单过滤：不在白名单里的会话直接忽略（不读取内容）
        if (!isChatAllowed(chatId)) return;

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
                return; // 失败就不打扰，等对方下一条
            }
            // 发送 hook 会把这条回复记进上下文
            [self sendReply:reply chatId:chatId];
        }];
    });
}

+ (void)recordSentMessage:(NSString *)content chatId:(NSString *)chatId {
    @try {
        if (content.length == 0 || chatId.length == 0) return;
        if (!isChatAllowed(chatId)) return;
        if (!isAutoMode()) return;
        // 自己发出的消息（手动发的和 AI 回复）都算“我”这一侧
        [[AIContext shared] appendAssistant:content chatId:chatId];
    } @catch (NSException *exception) {
        NSLog(kAITweakLogPrefix "记录发送消息异常: %@", exception);
    }
}

// 自己手动发送的命令：@AI 设置 / @AI 清空
+ (NSString *)commandFromContent:(NSString *)content {
    if (![content hasPrefix:kAITrigger]) return nil;
    NSString *question = [content substringFromIndex:kAITrigger.length];
    question = [question stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([question isEqualToString:@"设置"] || [question isEqualToString:@"settings"]) return @"settings";
    if ([question isEqualToString:@"清空"] || [question isEqualToString:@"reset"]) return @"clear";
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
    }
}

+ (void)sendReply:(NSString *)text chatId:(NSString *)chatId {
    if (text.length == 0 || chatId.length == 0) return;

    void (^send)(void) = ^{
        CMessageMgr *mgr = wechatMessageMgr();
        if (!mgr) {
            NSLog(kAITweakLogPrefix "获取 CMessageMgr 失败");
            return;
        }
        if (![mgr respondsToSelector:@selector(SendTextMessage:toUsrName:)]) {
            NSLog(kAITweakLogPrefix "当前微信版本没有 SendTextMessage:toUsrName:，需要更新接口");
            return;
        }
        g_sendingReply = YES;
        [mgr SendTextMessage:text toUsrName:chatId];
        g_sendingReply = NO;
        NSLog(kAITweakLogPrefix "已发送回复到 %@", chatId);
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
static void (*orig_SendTextMessage)(id, SEL, NSString *, NSString *);

static void swz_AsyncOnAddMsg(id self, SEL _cmd, id arg1, CMessageWrap *wrap) {
    if (orig_AsyncOnAddMsg) {
        orig_AsyncOnAddMsg(self, _cmd, arg1, wrap);
    }
    [WeChatAIHandler handleIncomingMessage:wrap];
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
    [WeChatAIHandler recordSentMessage:content chatId:usrName];
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
        NSLog(kAITweakLogPrefix "hook 安装成功: AsyncOnAddMsg:MsgWrap:");

        // 首次加载弹一次提示，方便确认注入是否成功
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            if ([defaults boolForKey:@"WeChatAIWelcomeShown"]) return;
            [defaults setBool:YES forKey:@"WeChatAIWelcomeShown"];
            [defaults synchronize];

            UIViewController *top = tweakTopViewController();
            if (!top) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"微信 AI 助手已加载"
                message:@"给自己发 @AI 设置 可打开配置页；自动模式下对方发消息即可自动回复。"
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [top presentViewController:alert animated:YES completion:nil];
        });
    } else {
        NSLog(kAITweakLogPrefix "没有找到 AsyncOnAddMsg:MsgWrap:，当前微信版本可能改了接口");
    }

    Method sendMethod = class_getInstanceMethod(cls, @selector(SendTextMessage:toUsrName:));
    if (sendMethod) {
        orig_SendTextMessage = (void *)method_getImplementation(sendMethod);
        method_setImplementation(sendMethod, (IMP)swz_SendTextMessage);
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

    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidFinishLaunchingNotification"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        retryInstall(10);
    }];

    // 兜底：如果通知已经发过，直接靠延时重试
    retryInstall(10);
}
