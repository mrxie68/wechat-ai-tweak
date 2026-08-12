#import "AISettings.h"
#import "AIConfig.h"

static NSString * const kAISettingsAutoPromptKey = @"WeChatAIAutoSystemPrompt";
static NSString * const kAISettingsAPIKeyKey = @"WeChatAIAPIKey";
static NSString * const kAISettingsModelKey = @"WeChatAIModel";
static NSString * const kAISettingsEnabledKey = @"WeChatAIEnabled";

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
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:kAISettingsModelKey];
    if (stored.length > 0) return stored;
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

@end
