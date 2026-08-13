#import "AIAPIClient.h"
#import "AIConfig.h"
#import "AISettings.h"

@implementation AIAPIClient

+ (instancetype)shared {
    static AIAPIClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

// 解析 Q:/A: 格式的聊天风格样本为 Few-Shot 消息对（最多 maxPairs 组）。
// 容错：跳过空行和未知前缀行；支持全角冒号“Q：”；内容首尾空白会被清理。
static NSArray<NSDictionary *> *aiParseFewShotSamples(NSString *samples, NSUInteger maxPairs) {
    NSMutableArray *msgs = [NSMutableArray array];
    if (samples.length == 0) return msgs;
    NSUInteger cap = maxPairs * 2;
    NSArray *lines = [samples componentsSeparatedByCharactersInSet:
                      [NSCharacterSet newlineCharacterSet]];
    for (NSString *raw in lines) {
        if (msgs.count >= cap) break;
        NSString *line = [raw stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length < 2) continue;
        unichar c0 = [line characterAtIndex:0];
        unichar c1 = [line characterAtIndex:1];
        if (c1 != ':' && c1 != 0xFF1A) continue;  // 0xFF1A = 全角冒号：
        NSString *role = nil;
        if (c0 == 'Q' || c0 == 'q') role = @"user";
        else if (c0 == 'A' || c0 == 'a') role = @"assistant";
        else continue;
        NSString *content = [[line substringFromIndex:2]
                             stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (content.length == 0) continue;
        [msgs addObject:@{@"role": role, @"content": content}];
    }
    return msgs;
}

+ (NSUInteger)fewShotMessageCount {
    return aiParseFewShotSamples([AISettings styleSamples], 4).count;
}

- (void)sendMessages:(NSArray<NSDictionary *> *)messages
         systemPrompt:(NSString *)systemPrompt
         styleProfile:(NSString *)styleProfile
         userProfile:(NSString *)userProfile
         friendInfo:(NSDictionary *)friendInfo
         timeoutInterval:(NSTimeInterval)timeoutInterval
         fewShotEnabled:(BOOL)fewShotEnabled
          completion:(void (^)(NSString *, NSError *))completion {

    NSURL *url = [NSURL URLWithString:[kAIBaseURL stringByAppendingString:@"/chat/completions"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", [AISettings apiKey]] forHTTPHeaderField:@"Authorization"];
    [request setTimeoutInterval:timeoutInterval > 0 ? timeoutInterval : 60];

    // 系统提示词 + 会话历史
    NSMutableArray *payload = [NSMutableArray array];
    NSString *finalPrompt = systemPrompt;
    NSArray *fewShot = @[];
    NSString *samples = fewShotEnabled ? [AISettings styleSamples] : @"";
    if (samples.length > 0) {
        fewShot = aiParseFewShotSamples(samples, 4);
        // 解析不出 Q:/A: 时退回纯文本注入，兼容以前粘贴的自由格式样本
        if (fewShot.count == 0) {
            finalPrompt = [finalPrompt stringByAppendingFormat:
                @"\n\n【你的真实聊天风格样本，请模仿这里的语气、用词和习惯来回复】\n%@", samples];
        }
    }
    if (styleProfile.length > 0) {
        finalPrompt = [finalPrompt stringByAppendingFormat:
            @"\n\n【你与这位好友聊天时的风格档案，请严格按这个风格说话】\n%@", styleProfile];
    }
    if (userProfile.length > 0) {
        finalPrompt = [finalPrompt stringByAppendingFormat:
            @"\n\n【关于我本人（你扮演的人）的基本信息：这些只属于“我”，聊天时以此为准，绝不能安到对方头上；没写到的信息一律不要编造】\n%@", userProfile];
    }
    if (friendInfo.count > 0) {
        NSString *call = friendInfo[@"call"] ?: @"";
        NSString *rel = friendInfo[@"relation"] ?: @"";
        NSString *fav = friendInfo[@"favor"] ?: @"";
        NSString *basic = friendInfo[@"basic"] ?: @"";
        NSString *note = friendInfo[@"note"] ?: @"";
        NSMutableString *fi = [NSMutableString stringWithString:@"\n\n【关于这位好友，决定说话的语气和分寸】"];
        if (call.length > 0) [fi appendFormat:@"\n称呼：%@", call];
        if (rel.length > 0) [fi appendFormat:@"\n关系：%@", rel];
        if (fav.length > 0) [fi appendFormat:@"\n好感度：%@", fav];
        if (basic.length > 0) [fi appendFormat:@"\n基本情况：%@", basic];
        if (note.length > 0) [fi appendFormat:@"\n备注：%@", note];
        finalPrompt = [finalPrompt stringByAppendingString:fi];
    }
    if (finalPrompt.length > 0) {
        [payload addObject:@{@"role": @"system", @"content": finalPrompt}];
    }
    // 顺序：system → Few-Shot 范例 → 真实聊天上下文
    if (fewShot.count > 0) {
        [payload addObjectsFromArray:fewShot];
    }
    [payload addObjectsFromArray:messages];

    NSDictionary *body = @{
        @"model": [AISettings model],
        @"messages": payload,
        @"max_tokens": @800,  // 限制输出长度，防模型长篇大论拖慢响应
        @"temperature": @([AISettings temperature]),
        @"frequency_penalty": @([AISettings frequencyPenalty]),
        @"presence_penalty": @([AISettings presencePenalty])
    };

    NSError *jsonError = nil;
    NSData *jsonData = nil;
    @try {
        jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    } @catch (NSException *e) {
        jsonError = [NSError errorWithDomain:@"WeChatAI"
                                        code:3
                                    userInfo:@{NSLocalizedDescriptionKey:
                                               [NSString stringWithFormat:@"请求序列化异常: %@", e]}];
        jsonData = nil;
    }
    if (!jsonData) {
        completion(nil, jsonError);
        return;
    }
    request.HTTPBody = jsonData;

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }

        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        NSLog(kAITweakLogPrefix "API HTTP 状态: %ld", (long)http.statusCode);
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSLog(kAITweakLogPrefix "API 响应: %@", json ?: @"（非JSON）");
        // HTTP 错误（401 Key 无效 / 402 余额不足 / 429 限流…）带状态码返回，便于弹窗精确提示
        if (http.statusCode >= 400) {
            NSString *errMsg = [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode];
            NSString *apiMsg = json[@"error"][@"message"];
            if (apiMsg.length > 0) {
                errMsg = [errMsg stringByAppendingFormat:@"：%@", apiMsg];
            }
            completion(nil, [NSError errorWithDomain:@"WeChatAI"
                                                code:http.statusCode
                                            userInfo:@{NSLocalizedDescriptionKey: errMsg}]);
            return;
        }

        // 即使 HTTP 200，响应里带 error 也视为失败，优先显示可读的错误信息
        NSString *apiErr = json[@"error"][@"message"];
        if (apiErr.length > 0) {
            NSString *errMsg = [NSString stringWithFormat:@"API 错误：%@", apiErr];
            completion(nil, [NSError errorWithDomain:@"WeChatAI"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: errMsg}]);
            return;
        }
        NSString *reply = json[@"choices"][0][@"message"][@"content"];
        if (reply.length == 0) {
            NSString *message = [NSString stringWithFormat:@"API 返回异常(HTTP %ld)，响应没有文本内容",
                                 (long)http.statusCode];
            completion(nil, [NSError errorWithDomain:@"WeChatAI"
                                                code:1
                                            userInfo:@{
                                                NSLocalizedDescriptionKey: message,
                                                @"rawResponse": json ?: @"",
                                            }]);
            return;
        }
        completion(reply, nil);
    }];
    [task resume];
}

@end
