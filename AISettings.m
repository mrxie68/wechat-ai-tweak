#import "AISettings.h"
#import "AIConfig.h"
#import <Security/Security.h>

static NSString * const kAIKeychainService = @"com.wechat-ai.deepseek-key";

static NSString * const kAISettingsAutoPromptKey = @"WeChatAIAutoSystemPrompt";
static NSString * const kAISettingsStyleSamplesKey = @"WeChatAIStyleSamples";
static NSString * const kAISettingsUserProfileKey = @"WeChatAIUserProfile";
static NSString * const kAISettingsAPIKeyKey = @"WeChatAIAPIKey";
static NSString * const kAISettingsModelKey = @"WeChatAIModel";
static NSString * const kAISettingsReplyModeKey = @"WeChatAIReplyMode";
static NSString * const kAISettingsEnabledKey = @"WeChatAIEnabled";
static NSString * const kAISettingsGroupQuestionOnlyKey = @"WeChatAIGroupQuestionOnly";
static NSString * const kAISettingsStickerLightReplyKey = @"WeChatAIStickerLightReply";
static NSString * const kAISettingsReplyDelayKey = @"WeChatAIReplyDelay";
static NSString * const kAISettingsTemperatureKey = @"WeChatAITemperature";
static NSString * const kAISettingsFrequencyPenaltyKey = @"WeChatAIFrequencyPenalty";
static NSString * const kAISettingsPresencePenaltyKey = @"WeChatAIPresencePenalty";
static NSString * const kAISettingsTypingSimulationKey = @"WeChatAITypingSimulation";
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

+(NSString *)userProfile {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kAISettingsUserProfileKey];
    if (stored.length > 0) return stored;
    return kAIUserProfile;
}

+(void)setUserProfile:(NSString *)profile {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (profile.length > 0) {
        [defaults setObject:profile forKey:kAISettingsUserProfileKey];
    } else {
        [defaults removeObjectForKey:kAISettingsUserProfileKey];
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

+(void)clearAllStyleProfiles {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *all = [defaults dictionaryRepresentation];
    for (NSString *key in all) {
        if ([key hasPrefix:@"WeChatAIStyleProfile_"]) {
            [defaults removeObjectForKey:key];
        }
    }
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

+(NSArray<NSDictionary *> *)allStyleProfiles {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *all = [defaults dictionaryRepresentation];
    NSMutableArray *profiles = [NSMutableArray array];
    NSString *prefix = @"WeChatAIStyleProfile_";
    for (NSString *key in all) {
        if ([key hasPrefix:prefix]) {
            NSString *chatId = [key substringFromIndex:prefix.length];
            id profile = all[key];
            if (chatId.length > 0 && [profile isKindOfClass:[NSString class]] &&
                ((NSString *)profile).length > 0) {
                [profiles addObject:@{@"chatId": chatId, @"profile": profile}];
            }
        }
    }
    [profiles sortUsingComparator:^NSComparisonResult(id a, id b) {
        return [a[@"chatId"] compare:b[@"chatId"]];
    }];
    return profiles;
}

+ (NSString *)apiKey {
    // 1. Keychain 优先（加密存储，越狱/取证工具也读不到）
    NSString *kc = [self keychainApiKey];
    if (kc.length > 0) return kc;
    // 2. 旧版 NSUserDefaults 迁移：读一次就搬进 Keychain 并清掉明文
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kAISettingsAPIKeyKey];
    if (stored.length > 0) {
        [self setApiKey:stored];
        return stored;
    }
    return kAIAPIKey;
}

+ (void)setApiKey:(NSString *)key {
    if (key.length > 0) {
        [self setKeychainApiKey:key];
    } else {
        [self deleteKeychainApiKey];
    }
    // 迁移后一律清掉 NSUserDefaults 明文
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kAISettingsAPIKeyKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)keychainApiKey {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kAIKeychainService,
        (__bridge id)kSecAttrAccount: @"deepseek",
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        NSData *data = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return @"";
}

+ (void)setKeychainApiKey:(NSString *)key {
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kAIKeychainService,
        (__bridge id)kSecAttrAccount: @"deepseek",
    };
    NSDictionary *attrs = @{
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    };
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    if (status == errSecSuccess) {
        SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attrs);
    } else {
        NSMutableDictionary *add = [query mutableCopy];
        [add addEntriesFromDictionary:attrs];
        SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
}

+ (void)deleteKeychainApiKey {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kAIKeychainService,
        (__bridge id)kSecAttrAccount: @"deepseek",
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
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

+(BOOL)groupQuestionOnly {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsGroupQuestionOnlyKey] == nil) return YES;
    return [defaults boolForKey:kAISettingsGroupQuestionOnlyKey];
}

+(void)setGroupQuestionOnly:(BOOL)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:kAISettingsGroupQuestionOnlyKey];
    [defaults synchronize];
}

+(BOOL)stickerLightReply {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsStickerLightReplyKey] == nil) return NO;
    return [defaults boolForKey:kAISettingsStickerLightReplyKey];
}

+(void)setStickerLightReply:(BOOL)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:kAISettingsStickerLightReplyKey];
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

+(double)temperature {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsTemperatureKey] == nil) return kAIRequestTemperature;
    return [defaults doubleForKey:kAISettingsTemperatureKey];
}

+(void)setTemperature:(double)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:value forKey:kAISettingsTemperatureKey];
    [defaults synchronize];
}

+(double)frequencyPenalty {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsFrequencyPenaltyKey] == nil) return kAIRequestFrequencyPenalty;
    return [defaults doubleForKey:kAISettingsFrequencyPenaltyKey];
}

+(void)setFrequencyPenalty:(double)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:value forKey:kAISettingsFrequencyPenaltyKey];
    [defaults synchronize];
}

+(double)presencePenalty {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsPresencePenaltyKey] == nil) return kAIRequestPresencePenalty;
    return [defaults doubleForKey:kAISettingsPresencePenaltyKey];
}

+(void)setPresencePenalty:(double)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:value forKey:kAISettingsPresencePenaltyKey];
    [defaults synchronize];
}

+(BOOL)typingSimulation {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kAISettingsTypingSimulationKey] == nil) return YES;
    return [defaults boolForKey:kAISettingsTypingSimulationKey];
}

+(void)setTypingSimulation:(BOOL)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:kAISettingsTypingSimulationKey];
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
