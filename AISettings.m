#import "AISettings.h"
#import "AIConfig.h"

static NSString * const kAISettingsAutoPromptKey = @"WeChatAIAutoSystemPrompt";
static NSString * const kAISettingsStyleSamplesKey = @"WeChatAIStyleSamples";
static NSString * const kAISettingsAPIKeyKey = @"WeChatAIAPIKey";
static NSString * const kAISettingsModelKey = @"WeChatAIModel";
static NSString * const kAISettingsReplyModeKey = @"WeChatAIReplyMode";
static NSString * const kAISettingsEnabledKey = @"WeChatAIEnabled";
static NSString * const kAISettingsReplyDelayKey = @"WeChatAIReplyDelay";
static NSString * const kAISettingsChatOverridesKey = @"WeChatAIChatOverrides";
static NSString * const kAISettingsSingleChatKey = @"WeChatAISingleChatEnabled";
static NSString * const kAISettingsGroupChatKey = @"WeChatAIGroupChatEnabled";

@implementation AISettings

+ (NSString *)autoSystemPrompt {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kAISettingsAutoPromptKey];
    if (stored.length > 0) return stored;
    return kAIAutoSystemPrompt;
}

+ (void)setAutoSystemPrompt:(NSString *)prompt {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (prompt.length > 0) {
        [defaults setObject:prompt forKey:kAISettingsAutoPromptKey];
    } else {
        [defaults removeObjectForKey:kAISettingsAutoPromptKey];
    }
    [defaults synchronize];
}

+ (NSString *)styleSamples {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kAISettingsStyleSamplesKey] ?: @"";
}

+ (void)setStyleSamples:(NSString *)samples {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (samples.length > 0) {
        [defaults setObject:samples forKey:kAISettingsStyleSamplesKey];
    } else {
        [defaults removeObjectForKey:kAISettingsStyleSamplesKey];
    }
    [defaults synchronize];
}

+ (NSString *)apiKey {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kAISettingsAPIKeyKey];
    if (stored.length > 0) return stored;
    return kAIAPIKey;
}

+ (void)setApiKey:(NSString *)key {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (key.length > 0) {
        [defaults setObject:key forKey:kAISettingsAPIKeyKey];
    } else {
        [defaults removeObjectForKey:kAISettingsAPIKeyKey];
    }
    [defaults synchronize];
}

+ (NSString *)model {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *stored = [defaults stringForKey:kAISettingsModelKey];
    if (stored.length > 0) {
        // 旧模型名已弃用：清掉旧值，回落到新默认
        if (![stored isEqualToString:@"deepseek-chat"] && ![stored isEqualToString:@"deepseek-reasoner"]) {
            return stored;
        }
        [defaults removeObjectForKey:kAISettingsModelKey];
    }
    return kAIModel;
}

+ (void)setModel:(NSString *)model {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (model.length > 0) {
        [defaults setObject:model forKey:kAISettingsModelKey];
    } else {
        [defaults removeObjectForKey:kAISettingsModelKey];
    }
    [defaults synchronize];
}

+ (NSString *)replyMode {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kAISettingsReplyModeKey];
    if ([stored isEqualToString:@"auto"] || [stored isEqualToString:@"trigger"]) return stored;
    return kAIReplyMode;
}

+ (void)setReplyMode:(NSString *)mode {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([mode isEqualToString:@"auto"] || [mode isEqualToString:@"trigger"]) {
        [defaults setObject:mode forKey:kAISettingsReplyModeKey];
    } else {
        [defaults removeObjectForKey:kAISettingsReplyModeKey];
    }
    [defaults synchronize];
}

+ (BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsEnabledKey] == nil) return YES; // 默认开
    return [defaults boolForKey:kAISettingsEnabledKey];
}

+ (void)setEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kAISettingsEnabledKey];
    [defaults synchronize];
}

+ (double)replyDelay {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsReplyDelayKey] == nil) return kAIReplyDelaySeconds;
    return [defaults doubleForKey:kAISettingsReplyDelayKey];
}

+ (void)setReplyDelay:(double)delay {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:delay forKey:kAISettingsReplyDelayKey];
    [defaults synchronize];
}

+ (BOOL)chatEnabled:(NSString *)chatId defaultEnabled:(BOOL)defaultEnabled {
    if (chatId.length == 0) return defaultEnabled;
    NSDictionary *overrides = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kAISettingsChatOverridesKey];
    NSNumber *value = overrides[chatId];
    if (value) return value.boolValue;
    return defaultEnabled;
}

+ (void)setChatEnabled:(BOOL)enabled chatId:(NSString *)chatId {
    if (chatId.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *overrides = [[defaults dictionaryForKey:kAISettingsChatOverridesKey] mutableCopy];
    if (!overrides) overrides = [NSMutableDictionary dictionary];
    overrides[chatId] = @(enabled);
    [defaults setObject:overrides forKey:kAISettingsChatOverridesKey];
    [defaults synchronize];
}

+ (BOOL)chatEnabled:(NSString *)chatId {
    BOOL isGroup = [chatId containsString:@"@chatroom"];
    // 类别总开关优先：单聊/群聊总开关关掉 → 这类会话全部硬关闭，单独设置也不生效
    if (isGroup ? ![self groupChatEnabled] : ![self singleChatEnabled]) return NO;
    return [self chatEnabled:chatId defaultEnabled:YES];
}

+ (BOOL)singleChatEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsSingleChatKey] == nil) return YES; // 默认开
    return [defaults boolForKey:kAISettingsSingleChatKey];
}

+ (void)setSingleChatEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kAISettingsSingleChatKey];
    [defaults synchronize];
}

+ (BOOL)groupChatEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsGroupChatKey] == nil) return NO; // 默认关（防误回复）
    return [defaults boolForKey:kAISettingsGroupChatKey];
}

+ (void)setGroupChatEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kAISettingsGroupChatKey];
    [defaults synchronize];
}

@end
