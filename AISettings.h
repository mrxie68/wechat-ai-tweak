#import <Foundation/Foundation.h>

// 微信内设置（NSUserDefaults 持久化，重启不丢）
@interface AISettings : NSObject

+ (NSString *)autoSystemPrompt;        // 有自定义值返回自定义值，否则返回 AIConfig.h 默认
+ (void)setAutoSystemPrompt:(NSString *)prompt; // 传空则恢复默认

@end
