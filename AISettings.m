#import "AISettings.h"
#import "AIConfig.h"

static NSString * const kAISettingsAutoPromptKey = @"WeChatAIAutoSystemPrompt";

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

@end
