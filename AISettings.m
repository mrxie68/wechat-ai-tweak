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
static NSString * const kAISettingsActivationPrefix = @"WeChatAIActivationKey_";
static NSString * const kAISettingsGroupQuestionOnlyKey = @"WeChatAIGroupQuestionOnly";
static NSString * const kAISettingsStickerLightReplyKey = @"WeChatAIStickerLightReply";
static NSString * const kAISettingsReplyDelayKey = @"WeChatAIReplyDelay";
static NSString * const kAISettingsTemperatureKey = @"WeChatAITemperature";
static NSString * const kAISettingsFrequencyPenaltyKey = @"WeChatAIFrequencyPenalty";
static NSString * const kAISettingsPresencePenaltyKey = @"WeChatAIPresencePenalty";
static NSString * const kAISettingsTypingSimulationKey = @"WeChatAITypingSimulation";
static NSString * const kAISettingsChatOverridesKey = @"WeChatAIChatOverrides";
static NSString * const kAISettingsProfilePrefix = @"WeChatAIStyleProfile_";

static NSString *g_currentAccount = nil;

@implementation AISettings

+(void)setCurrentAccount:(NSString *)usrName {
    @synchronized (self) {
        if (usrName.length == 0) return;
        if (![g_currentAccount isEqualToString:usrName]) {
            g_currentAccount = [usrName copy];
            [self migrateLegacyForCurrentAccount];
        }
    }
}

// 普通设置键：加账号后缀，切号即切换数据目录
+(NSString *)namespacedKey:(NSString *)base {
    @synchronized (self) {
        if (g_currentAccount.length == 0) return base;
        return [NSString stringWithFormat:@"%@_%@", base, g_currentAccount];
    }
}

+(NSString *)profileKeyForChatId:(NSString *)chatId {
    @synchronized (self) {
        if (g_currentAccount.length == 0) {
            return [kAISettingsProfilePrefix stringByAppendingString:chatId];
        }
        return [NSString stringWithFormat:@"%@%@_%@", kAISettingsProfilePrefix, g_currentAccount, chatId];
    }
}

+(NSString *)profilePrefixForCurrentAccount {
    @synchronized (self) {
        if (g_currentAccount.length == 0) return kAISettingsProfilePrefix;
        return [NSString stringWithFormat:@"%@%@_", kAISettingsProfilePrefix, g_currentAccount];
    }
}

// 首次设置账号时，把旧版全局数据搬进当前账号命名空间并清掉全局键
+(void)migrateLegacyForCurrentAccount {
    NSString *acc = g_currentAccount;
    if (acc.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *markerKey = [self namespacedKey:@"WeChatAISettingsMigrated"];
    if ([defaults boolForKey:markerKey]) return;
    [defaults setBool:YES forKey:markerKey];

    NSArray *legacyKeys = @[
        kAISettingsAutoPromptKey, kAISettingsStyleSamplesKey, kAISettingsUserProfileKey,
        kAISettingsModelKey, kAISettingsReplyModeKey, kAISettingsEnabledKey,
        kAISettingsGroupQuestionOnlyKey, kAISettingsStickerLightReplyKey,
        kAISettingsReplyDelayKey, kAISettingsTemperatureKey,
        kAISettingsFrequencyPenaltyKey, kAISettingsPresencePenaltyKey,
        kAISettingsTypingSimulationKey, kAISettingsChatOverridesKey,
    ];
    for (NSString *legacy in legacyKeys) {
        id value = [defaults objectForKey:legacy];
        if (value) {
            [defaults setObject:value forKey:[self namespacedKey:legacy]];
            [defaults removeObjectForKey:legacy];
        }
    }
    // 风格档案：WeChatAIStyleProfile_<chatId> → WeChatAIStyleProfile_<acc>_<chatId>
    NSDictionary *all = [defaults dictionaryRepresentation];
    for (NSString *key in all) {
        if ([key hasPrefix:kAISettingsProfilePrefix]) {
            NSString *suffix = [key substringFromIndex:kAISettingsProfilePrefix.length];
            [defaults setObject:all[key] forKey:[self profileKeyForChatId:suffix]];
            [defaults removeObjectForKey:key];
        }
    }
    // API Key：旧 Keychain（deepseek）→ 当前账号；顺带清理 NSUserDefaults 明文
    NSString *legacyKc = [self keychainApiKeyForAccount:@"deepseek"];
    if (legacyKc.length > 0) {
        [self setKeychainApiKey:legacyKc forAccount:acc];
        [self deleteKeychainApiKeyForAccount:@"deepseek"];
    }
    NSString *legacyPlain = [defaults stringForKey:kAISettingsAPIKeyKey];
    if (legacyPlain.length > 0) {
        [self setKeychainApiKey:legacyPlain forAccount:acc];
        [defaults removeObjectForKey:kAISettingsAPIKeyKey];
    }
    [defaults synchronize];
}

+ (NSString *)autoSystemPrompt {
    NSString *stored = [[NSUserDefaults standardUserDefaults]
                        stringForKey:[self namespacedKey:kAISettingsAutoPromptKey]];
    if (stored.length > 0) return stored;
    return kAIAutoSystemPrompt;
}

+ (void)setAutoSystemPrompt:(NSString *)prompt {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsAutoPromptKey];
    if (prompt.length > 0) {
        [defaults setObject:prompt forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

+ (NSString *)styleSamples {
    NSString *stored = [[NSUserDefaults standardUserDefaults]
                        stringForKey:[self namespacedKey:kAISettingsStyleSamplesKey]];
    if (stored.length > 0) return stored;
    return kAIStyleSamplesDefault;
}

+ (void)setStyleSamples:(NSString *)samples {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsStyleSamplesKey];
    if (samples.length > 0) {
        [defaults setObject:samples forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

+(NSString *)userProfile {
    NSString *stored = [[NSUserDefaults standardUserDefaults]
                        stringForKey:[self namespacedKey:kAISettingsUserProfileKey]];
    if (stored.length > 0) return stored;
    return kAIUserProfile;
}

+(void)setUserProfile:(NSString *)profile {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsUserProfileKey];
    if (profile.length > 0) {
        [defaults setObject:profile forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

+ (NSString *)styleProfileForChat:(NSString *)chatId {
    if (chatId.length == 0) return @"";
    return [[NSUserDefaults standardUserDefaults]
            stringForKey:[self profileKeyForChatId:chatId]] ?: @"";
}

+ (void)setStyleProfile:(NSString *)profile forChat:(NSString *)chatId {
    if (chatId.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self profileKeyForChatId:chatId];
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
    [defaults removeObjectForKey:[self profileKeyForChatId:chatId]];
    [defaults synchronize];
}

+(void)clearAllStyleProfiles {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *all = [defaults dictionaryRepresentation];
    NSString *prefix = [self profilePrefixForCurrentAccount];
    for (NSString *key in all) {
        if ([key hasPrefix:prefix]) {
            [defaults removeObjectForKey:key];
        }
    }
    [defaults synchronize];
}

+ (NSInteger)styleProfileCount {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSInteger count = 0;
    NSString *prefix = [self profilePrefixForCurrentAccount];
    for (NSString *key in all) {
        if ([key hasPrefix:prefix]) count++;
    }
    return count;
}

+(NSArray<NSDictionary *> *)allStyleProfiles {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *all = [defaults dictionaryRepresentation];
    NSMutableArray *profiles = [NSMutableArray array];
    NSString *prefix = [self profilePrefixForCurrentAccount];
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
    NSString *acc = g_currentAccount.length > 0 ? g_currentAccount : @"deepseek";
    NSString *kc = [self keychainApiKeyForAccount:acc];
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
    NSString *acc = g_currentAccount.length > 0 ? g_currentAccount : @"deepseek";
    if (key.length > 0) {
        [self setKeychainApiKey:key forAccount:acc];
    } else {
        [self deleteKeychainApiKeyForAccount:acc];
    }
    // 迁移后一律清掉 NSUserDefaults 明文
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kAISettingsAPIKeyKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)keychainApiKeyForAccount:(NSString *)account {
    if (account.length == 0) return @"";
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kAIKeychainService,
        (__bridge id)kSecAttrAccount: account,
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

+ (void)setKeychainApiKey:(NSString *)key forAccount:(NSString *)account {
    if (account.length == 0) return;
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kAIKeychainService,
        (__bridge id)kSecAttrAccount: account,
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

+ (void)deleteKeychainApiKeyForAccount:(NSString *)account {
    if (account.length == 0) return;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kAIKeychainService,
        (__bridge id)kSecAttrAccount: account,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
}

+ (NSString *)model {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsModelKey];
    NSString *stored = [defaults stringForKey:key];
    if (stored.length > 0) {
        // 旧模型名已弃用：清掉旧值，回落到新默认
        if (![stored isEqualToString:@"deepseek-chat"] && ![stored isEqualToString:@"deepseek-reasoner"]) {
            return stored;
        }
        [defaults removeObjectForKey:key];
    }
    return kAIModel;
}

+ (void)setModel:(NSString *)model {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsModelKey];
    if (model.length > 0) {
        [defaults setObject:model forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

+ (NSString *)replyMode {
    NSString *stored = [[NSUserDefaults standardUserDefaults]
                        stringForKey:[self namespacedKey:kAISettingsReplyModeKey]];
    if ([stored isEqualToString:@"auto"] || [stored isEqualToString:@"trigger"]) return stored;
    return kAIReplyMode;
}

+ (void)setReplyMode:(NSString *)mode {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsReplyModeKey];
    if ([mode isEqualToString:@"auto"] || [mode isEqualToString:@"trigger"]) {
        [defaults setObject:mode forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

+ (BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsEnabledKey];
    if ([defaults objectForKey:key] == nil) return YES; // 默认开
    return [defaults boolForKey:key];
}

+ (void)setEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:[self namespacedKey:kAISettingsEnabledKey]];
    [defaults synchronize];
}

+(BOOL)isAccountActivated:(NSString *)usrName {
    if (usrName.length == 0) return NO;
    NSString *stored = [[NSUserDefaults standardUserDefaults]
                        stringForKey:[kAISettingsActivationPrefix stringByAppendingString:usrName]];
    return stored.length > 0 && [stored isEqualToString:kAIActivationKey];
}

+(void)setActivationKey:(NSString *)key forAccount:(NSString *)usrName {
    if (usrName.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *storeKey = [kAISettingsActivationPrefix stringByAppendingString:usrName];
    if (key.length > 0) {
        [defaults setObject:key forKey:storeKey];
    } else {
        [defaults removeObjectForKey:storeKey];
    }
    [defaults synchronize];
}

+(void)deactivateAccount:(NSString *)usrName {
    [self setActivationKey:nil forAccount:usrName];
}

+(BOOL)groupQuestionOnly {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsGroupQuestionOnlyKey];
    if ([defaults objectForKey:key] == nil) return YES;
    return [defaults boolForKey:key];
}

+(void)setGroupQuestionOnly:(BOOL)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:[self namespacedKey:kAISettingsGroupQuestionOnlyKey]];
    [defaults synchronize];
}

+(BOOL)stickerLightReply {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsStickerLightReplyKey];
    if ([defaults objectForKey:key] == nil) return NO;
    return [defaults boolForKey:key];
}

+(void)setStickerLightReply:(BOOL)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:[self namespacedKey:kAISettingsStickerLightReplyKey]];
    [defaults synchronize];
}

+ (double)replyDelay {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsReplyDelayKey];
    if ([defaults objectForKey:key] == nil) return kAIReplyDelaySeconds;
    return [defaults doubleForKey:key];
}

+ (void)setReplyDelay:(double)delay {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:delay forKey:[self namespacedKey:kAISettingsReplyDelayKey]];
    [defaults synchronize];
}

+(double)temperature {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsTemperatureKey];
    if ([defaults objectForKey:key] == nil) return kAIRequestTemperature;
    return [defaults doubleForKey:key];
}

+(void)setTemperature:(double)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:value forKey:[self namespacedKey:kAISettingsTemperatureKey]];
    [defaults synchronize];
}

+(double)frequencyPenalty {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsFrequencyPenaltyKey];
    if ([defaults objectForKey:key] == nil) return kAIRequestFrequencyPenalty;
    return [defaults doubleForKey:key];
}

+(void)setFrequencyPenalty:(double)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:value forKey:[self namespacedKey:kAISettingsFrequencyPenaltyKey]];
    [defaults synchronize];
}

+(double)presencePenalty {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsPresencePenaltyKey];
    if ([defaults objectForKey:key] == nil) return kAIRequestPresencePenalty;
    return [defaults doubleForKey:key];
}

+(void)setPresencePenalty:(double)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:value forKey:[self namespacedKey:kAISettingsPresencePenaltyKey]];
    [defaults synchronize];
}

+(BOOL)typingSimulation {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsTypingSimulationKey];
    if ([defaults objectForKey:key] == nil) return YES;
    return [defaults boolForKey:key];
}

+(void)setTypingSimulation:(BOOL)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:[self namespacedKey:kAISettingsTypingSimulationKey]];
    [defaults synchronize];
}

+ (BOOL)chatEnabled:(NSString *)chatId defaultEnabled:(BOOL)defaultEnabled {
    if (chatId.length == 0) return defaultEnabled;
    NSDictionary *overrides = [[NSUserDefaults standardUserDefaults]
                               dictionaryForKey:[self namespacedKey:kAISettingsChatOverridesKey]];
    NSNumber *value = overrides[chatId];
    if (value) return value.boolValue;
    return defaultEnabled;
}

+ (void)setChatEnabled:(BOOL)enabled chatId:(NSString *)chatId {
    if (chatId.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [self namespacedKey:kAISettingsChatOverridesKey];
    NSMutableDictionary *overrides = [[defaults dictionaryForKey:key] mutableCopy];
    if (!overrides) overrides = [NSMutableDictionary dictionary];
    overrides[chatId] = @(enabled);
    [defaults setObject:overrides forKey:key];
    [defaults synchronize];
}

+ (BOOL)chatEnabled:(NSString *)chatId {
    // 默认全部关闭；只有聊天信息页的“AI 助手”开关单独开过的会话才回复
    return [self chatEnabled:chatId defaultEnabled:NO];
}

@end
