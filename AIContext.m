#import "AIContext.h"
#import "AIConfig.h"

@interface AIContext ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *histories;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastTimestamps;
@end

@implementation AIContext {
    NSUInteger _epoch;
}

+ (instancetype)shared {
    static AIContext *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _histories = [NSMutableDictionary dictionary];
        _lastTimestamps = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray<NSDictionary *> *)messagesForChat:(NSString *)chatId {
    @synchronized (self.histories) {
        return [self.histories[chatId] copy];
    }
}

- (void)appendUser:(NSString *)text timestamp:(NSTimeInterval)timestamp chatId:(NSString *)chatId {
    [self appendMessage:text role:@"user" timestamp:timestamp chatId:chatId];
}

- (void)appendAssistant:(NSString *)text timestamp:(NSTimeInterval)timestamp chatId:(NSString *)chatId {
    [self appendMessage:text role:@"assistant" timestamp:timestamp chatId:chatId];
}

- (void)appendMessage:(NSString *)text
                 role:(NSString *)role
            timestamp:(NSTimeInterval)timestamp
               chatId:(NSString *)chatId {
    @synchronized (self.histories) {
        NSMutableArray *messages = self.histories[chatId];
        if (!messages) {
            messages = [NSMutableArray array];
            self.histories[chatId] = messages;
        }

        // 时间感知：与上一条间隔超过阈值视为新话题，注入系统提示并强制新起一条
        NSString *finalText = text;
        NSNumber *lastTs = self.lastTimestamps[chatId];
        BOOL newTopic = NO;
        if (lastTs && timestamp > lastTs.doubleValue &&
            timestamp - lastTs.doubleValue > kAIContextNewTopicInterval) {
            newTopic = YES;
            finalText = [@"【系统提示：距离上次聊天已过去一段时间，这是一个全新的话题】\n"
                         stringByAppendingString:finalText];
        }
        self.lastTimestamps[chatId] = @(timestamp);

        // 同角色合并：微信连发短句（“在吗”[回车]“那个代码报错了”）合并成一条，
        // 保持一问一答的 ChatML 结构；跨新话题不合并，超长不合并
        NSDictionary *last = messages.lastObject;
        BOOL merged = NO;
        if (!newTopic && last && [last[@"role"] isEqualToString:role]) {
            NSString *lastContent = last[@"content"] ?: @"";
            NSString *combined = [lastContent stringByAppendingFormat:@"\n%@", finalText];
            if (combined.length <= kAIContextMergeMaxLength) {
                [messages replaceObjectAtIndex:messages.count - 1
                                    withObject:@{@"role": role, @"content": combined}];
                merged = YES;
            }
        }
        if (!merged) {
            [messages addObject:@{@"role": role, @"content": finalText}];
        }

        // 只保留最近 kAIMaxContextMessages 条
        while (messages.count > kAIMaxContextMessages) {
            [messages removeObjectAtIndex:0];
        }
    }
}

- (void)clearChat:(NSString *)chatId {
    @synchronized (self.histories) {
        [self.histories removeObjectForKey:chatId];
        [self.lastTimestamps removeObjectForKey:chatId];
        _epoch++;
    }
}

- (void)clearAll {
    @synchronized (self.histories) {
        [self.histories removeAllObjects];
        [self.lastTimestamps removeAllObjects];
        _epoch++;
    }
}

- (NSUInteger)epoch {
    @synchronized (self.histories) {
        return _epoch;
    }
}

@end
