//
//  RAILLMProvider.h
//  RuntimeAI
//
//  大模型供应商无关的抽象协议。SDK 上层不感知具体厂商, 通过依赖注入更换实现。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 一条对话消息。@{@"role": @"system"|@"user"|@"assistant", @"content": NSString}
typedef NSDictionary<NSString *, NSString *> RAILLMMessage;

/// 大模型供应商抽象协议。
@protocol RAILLMProvider <NSObject>

@required

/// 发起一次多轮对话。
/// - Parameters:
///   - messages: 对话历史 (role + content 字典数组)
///   - completion: 完整回复文本回调 (主线程)
- (void)chatWithMessages:(NSArray<RAILLMMessage *> *)messages
              completion:(void (^)(NSString * _Nullable reply, NSError * _Nullable error))completion;

@optional

/// 流式对话, 逐 token 回调 (可选, 用于悬浮窗打字机效果)。
- (void)streamChatWithMessages:(NSArray<RAILLMMessage *> *)messages
                       onToken:(void (^)(NSString *token))onToken
                        onDone:(void (^)(NSString * _Nullable full, NSError * _Nullable error))onDone;

/// 供应商显示名。
- (NSString *)providerName;

@end

NS_ASSUME_NONNULL_END