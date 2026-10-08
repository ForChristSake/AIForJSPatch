//
//  RAIOpenAICompatibleProvider.m
//  RuntimeAI
//

#import "RAIOpenAICompatibleProvider.h"

@implementation RAIOpenAICompatibleProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _endpoint = @"https://api.openai.com/v1/chat/completions";
        _model = @"gpt-4o-mini";
        _maxTokens = 1024;
        _timeoutInterval = 60.0;
    }
    return self;
}

- (instancetype)initWithEndpoint:(NSString *)endpoint
                          apiKey:(NSString *)apiKey
                           model:(NSString *)model {
    self = [self init];
    if (self) {
        _endpoint = endpoint;
        _apiKey = apiKey;
        if (model.length) _model = model;
    }
    return self;
}

- (NSString *)providerName {
    return @"OpenAI-Compatible";
}

#pragma mark - RAILLMProvider

- (void)chatWithMessages:(NSArray<RAILLMMessage *> *)messages
              completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    NSAssert(completion != nil, @"completion 不能为空");

    NSURL *url = [NSURL URLWithString:self.endpoint];
    if (!url) {
        completion(nil, [NSError errorWithDomain:@"RuntimeAI.LLM" code:201
                                        userInfo:@{NSLocalizedDescriptionKey: @"endpoint 无效"}]);
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (self.apiKey.length) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey]
            forHTTPHeaderField:@"Authorization"];
    }
    req.timeoutInterval = self.timeoutInterval;

    NSDictionary *body = @{
        @"model": self.model ?: @"",
        @"messages": messages ?: @[],
        @"max_tokens": @(self.maxTokens),
        @"temperature": @0.7,
    };
    NSError *jsonErr = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (jsonErr) {
        completion(nil, jsonErr);
        return;
    }
    req.HTTPBody = bodyData;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:
        [NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req
        completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(nil, error);
                return;
            }
            NSString *text = [self _extractReplyFromData:data response:response error:&error];
            if (error) {
                completion(nil, error);
                return;
            }
            completion(text, nil);
        });
    }];
    [task resume];
}

- (void)streamChatWithMessages:(NSArray<RAILLMMessage *> *)messages
                       onToken:(void (^)(NSString *))onToken
                        onDone:(void (^)(NSString * _Nullable, NSError * _Nullable))onDone {
    // 参考实现: 简化处理, 先完整请求再用逐字回调模拟流式。真实场景应改用 SSE 逐块解析。
    NSString *base = [self.endpoint stringByReplacingOccurrencesOfString:@"/chat/completions"
                                                              withString:@"/chat/completions"];
    [self chatWithMessages:messages completion:^(NSString *reply, NSError *error) {
        if (error) {
            if (onDone) onDone(nil, error);
            return;
        }
        NSArray<NSString *> *chars = [self _charactersOf:reply];
        __block NSString *full = @"";
        for (NSString *c in chars) {
            full = [full stringByAppendingString:c];
            if (onToken) onToken(c);
        }
        if (onDone) onDone(reply, nil);
    }];
}

#pragma mark - 解析响应

- (NSString *)_extractReplyFromData:(NSData *)data
                           response:(NSURLResponse *)response
                              error:(NSError * _Nullable __autoreleasing *)error {
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    if (http.statusCode < 200 || http.statusCode >= 300) {
        if (error) *error = [NSError errorWithDomain:@"RuntimeAI.LLM" code:http.statusCode
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode]}];
        return nil;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (*error) return nil;
    NSArray *choices = json[@"choices"];
    NSDictionary *first = choices.firstObject;
    NSString *content = first[@"message"][@"content"];
    // 兼容某些以 text 字段返回的中转。
    if (!content) content = first[@"text"];
    if (!content) {
        if (error) *error = [NSError errorWithDomain:@"RuntimeAI.LLM" code:202
            userInfo:@{NSLocalizedDescriptionKey: @"响应中未找到 content 字段"}];
        return nil;
    }
    return content;
}

- (NSArray<NSString *> *)_charactersOf:(NSString *)s {
    NSMutableArray *arr = [NSMutableArray array];
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length)
                          options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString * _Nullable sub, NSRange r, NSRange en, BOOL *stop) {
        [arr addObject:sub];
    }];
    return arr;
}

@end