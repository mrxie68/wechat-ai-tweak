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
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kAISettingsStyleSamplesKey];
    if (stored.length > 0) return stored;
    return kAIStyleSamplesDefault;
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

+ (NSString *)styleProfileForChat:(NSString *)chatId {
    if (chatId.length == 0) return @"";
    return [[NSUserDefaults standardUserDefaults] stringForKey:
            [NSString stringWithFormat:@"%@%@", @"WeChatAIStyleProfile_", chatId]] ?: @"";
}

+ (void)setStyleProfile:(NSString *)profile forChat:(NSString *)chatId {
    if (chatId.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [NSString stringWithFormat:@"%@%@", @"WeChatAIStyleProfile_", chatId];
    if (profile.length > 0) {
        if (profile.length > 2500) {
            profile = [profile substringToIndex:2500];
        }
        [defaults setObject:profile forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

+ (void)clearStyleProfileForChat:(NSString *)chatId {
    if (chatId.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:
     [NSString stringWithFormat:@"%@%@", @"WeChatAIStyleProfile_", chatId]];
    [defaults synchronize];
}

+ (NSInteger)styleProfileCount {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSInteger count = 0;
    for (NSString *key in all) {
        if ([key hasPrefix:@"WeChatAIStyleProfile_"]) count++;
    }
    return count;
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
    // 默认全部关闭；只有聊天信息页的“AI 助手”开关单独开过的会话才回复
    return [self chatEnabled:chatId defaultEnabled:NO];
}

@end
