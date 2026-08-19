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
        if (c1 != ':' && c1 != 0xFF1A) continue;
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

static NSString *aiProviderKeyFromBaseURL(NSString *baseURL) {
    NSString *lower = [baseURL.lowercaseString stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([lower containsString:@"bigmodel.cn"]) return @"zhipu";
    if ([lower containsString:@"deepseek.com"]) return @"deepseek";
    return @"custom";
}

static NSString *aiNormalizedBaseURL(NSString *baseURL) {
    NSString *trimmed = [baseURL stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([trimmed hasSuffix:@"/"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    NSArray<NSString *> *suffixes = @[@"/chat/completions", @"/v1/chat/completions"];
    NSString *lower = trimmed.lowercaseString;
    for (NSString *suffix in suffixes) {
        if ([lower hasSuffix:suffix]) {
            trimmed = [trimmed substringToIndex:trimmed.length - suffix.length];
            break;
        }
    }
    return trimmed;
}

static NSString *aiStringFromContentNode(id node) {
    if ([node isKindOfClass:[NSString class]]) {
        return [(NSString *)node stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([node isKindOfClass:[NSArray class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id item in (NSArray *)node) {
            NSString *part = aiStringFromContentNode(item);
            if (part.length > 0) [parts addObject:part];
        }
        return [parts componentsJoinedByString:@""];
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)node;
        NSString *text = aiStringFromContentNode(dict[@"text"]);
        if (text.length > 0) return text;
        NSString *content = aiStringFromContentNode(dict[@"content"]);
        if (content.length > 0) return content;
    }
    return @"";
}

static NSString *aiAPIErrorMessage(NSDictionary *json) {
    if (![json isKindOfClass:[NSDictionary class]]) return @"";
    id err = json[@"error"];
    if ([err isKindOfClass:[NSDictionary class]]) {
        NSString *msg = aiStringFromContentNode(err[@"message"]);
        if (msg.length > 0) return msg;
        msg = aiStringFromContentNode(err[@"msg"]);
        if (msg.length > 0) return msg;
    }
    NSString *message = aiStringFromContentNode(json[@"message"]);
    if (message.length > 0) return message;
    return aiStringFromContentNode(json[@"msg"]);
}

static NSString *aiReplyFromJSON(NSDictionary *json) {
    if (![json isKindOfClass:[NSDictionary class]]) return @"";
    NSArray *choices = json[@"choices"];
    if ([choices isKindOfClass:[NSArray class]] && choices.count > 0) {
        NSDictionary *first = [choices firstObject];
        if ([first isKindOfClass:[NSDictionary class]]) {
            NSString *reply = aiStringFromContentNode(first[@"message"][@"content"]);
            if (reply.length > 0) return reply;
            reply = aiStringFromContentNode(first[@"delta"][@"content"]);
            if (reply.length > 0) return reply;
            reply = aiStringFromContentNode(first[@"text"]);
            if (reply.length > 0) return reply;
            reply = aiStringFromContentNode(first[@"content"]);
            if (reply.length > 0) return reply;
        }
    }
    NSString *reply = aiStringFromContentNode(json[@"data"][@"content"]);
    if (reply.length > 0) return reply;
    return aiStringFromContentNode(json[@"content"]);
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

    NSString *baseURL = aiNormalizedBaseURL([AISettings baseURL]);
    NSString *provider = aiProviderKeyFromBaseURL(baseURL);
    NSURL *url = [NSURL URLWithString:[baseURL stringByAppendingString:@"/chat/completions"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", [AISettings apiKey]] forHTTPHeaderField:@"Authorization"];
    [request setTimeoutInterval:timeoutInterval > 0 ? timeoutInterval : 60];

    NSMutableArray *payload = [NSMutableArray array];
    NSString *priorityPrompt = @"【回复优先级】先接住对方刚发来的这句话，再考虑语气模仿；不要为了展示风格主动引入旧话题。正常情况下，对方发来一句就要自然接一句，哪怕只是短回应，也别无故沉默。表达方式优先模仿本人最近真实发言，事实只来自当前聊天、明确档案和基础信息；不确定就简短反问、承认记不清，别硬编。只输出准备发给对方的聊天文本，不要解释分析过程。\n\n";
    NSString *finalPrompt = [priorityPrompt stringByAppendingString:(systemPrompt ?: @"")];

    NSArray *fewShot = @[];
    NSString *samples = fewShotEnabled ? [AISettings styleSamples] : @"";
    if (samples.length > 0) {
        fewShot = aiParseFewShotSamples(samples, 4);
        if (fewShot.count == 0) {
            finalPrompt = [finalPrompt stringByAppendingFormat:
                @"\n\n【本人手动提供的语气样本：只模仿表达方式，不把里面的地点、经历、喜好当成事实】\n%@", samples];
        }
    }
    if (styleProfile.length > 0) {
        finalPrompt = [finalPrompt stringByAppendingFormat:
            @"\n\n【本人最近真实发言样本与已学习语气档案：优先模仿句长、口头禅、标点和分寸；只模仿说法，不复制样本中的事实】\n%@", styleProfile];
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
    if (fewShot.count > 0) {
        [payload addObjectsFromArray:fewShot];
    }
    [payload addObjectsFromArray:messages];

    NSMutableDictionary *body = [@{
        @"model": [AISettings model] ?: @"",
        @"messages": payload,
        @"max_tokens": @320,
        @"temperature": @([AISettings temperature])
    } mutableCopy];
    // 智谱兼容层在某些模型上对惩罚项更敏感，先用最小稳定参数集。
    if (![provider isEqualToString:@"zhipu"]) {
        body[@"frequency_penalty"] = @([AISettings frequencyPenalty]);
        body[@"presence_penalty"] = @([AISettings presencePenalty]);
    }

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
        NSString *rawText = data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSLog(kAITweakLogPrefix "API HTTP 状态: %ld", (long)http.statusCode);
        NSLog(kAITweakLogPrefix "API 响应: %@", json ?: (rawText.length > 0 ? rawText : @"（非JSON）"));

        NSString *apiMsg = aiAPIErrorMessage(json);
        if (http.statusCode >= 400) {
            NSString *errMsg = [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode];
            if (apiMsg.length > 0) {
                errMsg = [errMsg stringByAppendingFormat:@"：%@", apiMsg];
            } else if (rawText.length > 0) {
                NSString *snippet = rawText.length > 180 ? [rawText substringToIndex:180] : rawText;
                errMsg = [errMsg stringByAppendingFormat:@"：%@", snippet];
            }
            completion(nil, [NSError errorWithDomain:@"WeChatAI"
                                                code:http.statusCode
                                            userInfo:@{
                                                NSLocalizedDescriptionKey: errMsg,
                                                @"rawResponse": rawText ?: @"",
                                            }]);
            return;
        }

        if (apiMsg.length > 0) {
            NSString *errMsg = [NSString stringWithFormat:@"API 错误：%@", apiMsg];
            completion(nil, [NSError errorWithDomain:@"WeChatAI"
                                                code:2
                                            userInfo:@{
                                                NSLocalizedDescriptionKey: errMsg,
                                                @"rawResponse": rawText ?: @"",
                                            }]);
            return;
        }

        NSString *reply = aiReplyFromJSON(json);
        if (reply.length == 0) {
            NSString *message = [NSString stringWithFormat:@"API 返回异常(HTTP %ld)，响应没有文本内容",
                                 (long)http.statusCode];
            completion(nil, [NSError errorWithDomain:@"WeChatAI"
                                                code:1
                                            userInfo:@{
                                                NSLocalizedDescriptionKey: message,
                                                @"rawResponse": rawText.length > 0 ? rawText : (json ?: @""),
                                            }]);
            return;
        }
        completion(reply, nil);
    }];
    [task resume];
}

@end