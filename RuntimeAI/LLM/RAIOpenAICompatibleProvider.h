//
//  RAIOpenAICompatibleProvider.h
//  RuntimeAI
//
//  对标 OpenAI Chat Completions 协议的参考实现, 兼容大部分国产模型与自托管中转。
//

#import <Foundation/Foundation.h>
#import "RAILLMProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface RAIOpenAICompatibleProvider : NSObject <RAILLMProvider>

/// 协议端点, 例如 https://api.openai.com/v1/chat/completions 或其它兼容地址。
@property (nonatomic, copy) NSString *endpoint;

/// API Key (建议只在内测注入, 不随二进制分发)。
@property (nonatomic, copy) NSString *apiKey;

/// 模型名, 默认 @"gpt-4o-mini" (可按厂商覆盖)。
@property (nonatomic, copy) NSString *model;

/// 最大生成 token 数, 默认 1024。
@property (nonatomic, assign) NSInteger maxTokens;

/// 请求超时, 默认 60 秒。
@property (nonatomic, assign) NSTimeInterval timeoutInterval;

/// 便捷初始化。
- (instancetype)initWithEndpoint:(NSString *)endpoint
                          apiKey:(NSString *)apiKey
                           model:(NSString *)model;

@end

NS_ASSUME_NONNULL_END