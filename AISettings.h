#import <Foundation/Foundation.h>

// 微信内设置（NSUserDefaults 持久化，重启不丢）
@interface AISettings : NSObject

+ (NSString *)autoSystemPrompt;        // 有自定义值返回自定义值，否则返回 AIConfig.h 默认
+ (void)setAutoSystemPrompt:(NSString *)prompt; // 传空则恢复默认
+ (NSString *)styleSamples;            // 聊天风格样本（可空，AI 会模仿这里的语气）
+ (void)setStyleSamples:(NSString *)samples;
+ (NSString *)apiKey;                  // 同理
+ (void)setApiKey:(NSString *)key;
+ (NSString *)model;
+ (void)setModel:(NSString *)model;
+ (NSString *)replyMode;              // @"auto" / @"trigger"，默认 kAIReplyMode
+ (void)setReplyMode:(NSString *)mode;
+ (BOOL)enabled;                       // 机器人总开关（默认开）
+ (void)setEnabled:(BOOL)enabled;
+ (double)replyDelay;                  // 思考延迟（秒）
+ (void)setReplyDelay:(double)delay;
+ (BOOL)chatEnabled:(NSString *)chatId defaultEnabled:(BOOL)defaultEnabled; // 会话级开关
+ (void)setChatEnabled:(BOOL)enabled chatId:(NSString *)chatId;
+ (BOOL)chatEnabled:(NSString *)chatId;   // 默认关闭，只有聊天信息页单独开过才回

@end
