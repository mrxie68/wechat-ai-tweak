#import "AIAPIClient.h"
#import "AIConfig.h"

@implementation AIAPIClient

+ (instancetype)shared {
    static AIAPIClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)sendMessages:(NSArray<NSDictionary *> *)messages
         systemPrompt:(NSString *)systemPrompt
          completion:(void (^)(NSString *, NSError *))completion {

    NSURL *url = [NSURL URLWithString:[kAIBaseURL stringByAppendingString:@"/chat/completions"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", kAIAPIKey] forHTTPHeaderField:@"Authorization"];
    [request setTimeoutInterval:60];

    // 系统提示词 + 会话历史
    NSMutableArray *payload = [NSMutableArray array];
    if (systemPrompt.length > 0) {
        [payload addObject:@{@"role": @"system", @"content": systemPrompt}];
    }
    [payload addObjectsFromArray:messages];

    NSDictionary *body = @{
        @"model": kAIModel,
        @"messages": payload,
        @"temperature": @0.7
    };

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
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
        NSString *reply = json[@"choices"][0][@"message"][@"content"];
        if (reply.length == 0) {
            NSString *message = [NSString stringWithFormat:@"API 返回异常: %@", json];
            completion(nil, [NSError errorWithDomain:@"WeChatAI"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: message}]);
            return;
        }
        completion(reply, nil);
    }];
    [task resume];
}

@end
