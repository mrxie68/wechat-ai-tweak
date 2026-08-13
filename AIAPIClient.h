#import <Foundation/Foundation.h>

// 调用 OpenAI 兼容接口（/chat/completions）
@interface AIAPIClient : NSObject

+ (instancetype)shared;

// 当前“聊天风格样本”能解析出的 Few-Shot 消息条数（0 = 旧格式纯文本兜底）
+ (NSUInteger)fewShotMessageCount;

- (void)sendMessages:(NSArray<NSDictionary *> *)messages
         systemPrompt:(NSString *)systemPrompt
         styleProfile:(NSString *)styleProfile
         userProfile:(NSString *)userProfile
         friendInfo:(NSDictionary *)friendInfo
         timeoutInterval:(NSTimeInterval)timeoutInterval
         fewShotEnabled:(BOOL)fewShotEnabled
          completion:(void (^)(NSString *reply, NSError *error))completion;

@end
