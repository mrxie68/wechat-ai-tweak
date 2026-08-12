#import "AIContext.h"
#import "AIConfig.h"

@interface AIContext ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *histories;
@end

@implementation AIContext

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
    }
    return self;
}

- (NSArray<NSDictionary *> *)messagesForChat:(NSString *)chatId {
    @synchronized (self.histories) {
        return [self.histories[chatId] copy];
    }
}

- (void)appendUser:(NSString *)text chatId:(NSString *)chatId {
    [self appendMessage:@{@"role": @"user", @"content": text} chatId:chatId];
}

- (void)appendAssistant:(NSString *)text chatId:(NSString *)chatId {
    [self appendMessage:@{@"role": @"assistant", @"content": text} chatId:chatId];
}

- (void)appendMessage:(NSDictionary *)message chatId:(NSString *)chatId {
    @synchronized (self.histories) {
        NSMutableArray *messages = self.histories[chatId];
        if (!messages) {
            messages = [NSMutableArray array];
            self.histories[chatId] = messages;
        }
        [messages addObject:message];
        // 只保留最近 kAIMaxContextMessages 条
        while (messages.count > kAIMaxContextMessages) {
            [messages removeObjectAtIndex:0];
        }
    }
}

- (void)clearChat:(NSString *)chatId {
    @synchronized (self.histories) {
        [self.histories removeObjectForKey:chatId];
    }
}

@end
