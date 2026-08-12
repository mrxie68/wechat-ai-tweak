#import <Foundation/Foundation.h>

// 调用 OpenAI 兼容接口（/chat/completions）
@interface AIAPIClient : NSObject

+ (instancetype)shared;

- (void)sendMessages:(NSArray<NSDictionary *> *)messages
         systemPrompt:(NSString *)systemPrompt
         styleProfile:(NSString *)styleProfile
          completion:(void (^)(NSString *reply, NSError *error))completion;

@end
