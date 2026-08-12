#import <Foundation/Foundation.h>

// 每个会话的上下文历史（内存中，重启微信后清空）
@interface AIContext : NSObject

+ (instancetype)shared;

// 取某个会话的历史消息（[{role, content}, ...]）
- (NSArray<NSDictionary *> *)messagesForChat:(NSString *)chatId;

- (void)appendUser:(NSString *)text chatId:(NSString *)chatId;
- (void)appendAssistant:(NSString *)text chatId:(NSString *)chatId;
- (void)clearChat:(NSString *)chatId;
- (void)clearAll;
- (NSUInteger)epoch;   // 清空次数，用于丢弃清空时还在路上的回复

@end
