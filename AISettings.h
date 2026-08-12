#import <Foundation/Foundation.h>

// 微信内设置（NSUserDefaults 持久化，重启不丢）
@interface AISettings : NSObject

+ (NSString *)autoSystemPrompt;        // 有自定义值返回自定义值，否则返回 AIConfig.h 默认
+ (void)setAutoSystemPrompt:(NSString *)prompt; // 传空则恢复默认
+ (NSString *)apiKey;                  // 同理
+ (void)setApiKey:(NSString *)key;
+ (NSString *)model;
+ (void)setModel:(NSString *)model;
+ (BOOL)enabled;                       // 机器人总开关（默认开）
+ (void)setEnabled:(BOOL)enabled;
+ (double)replyDelay;                  // 思考延迟（秒）
+ (void)setReplyDelay:(double)delay;

@end
