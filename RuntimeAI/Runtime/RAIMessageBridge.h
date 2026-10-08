//
//  RAIMessageBridge.h
//  RuntimeAI
//
//  基于 NSProxy 的动态转发桥: 为任意目标对象包一层 "调用记录 + 透传" 的外壳。
//  可选模块: 适用于对象级调用与调用日志注入场景。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 转发回调: 每次向被代理对象发送消息时触发。可用来打日志 / 统计。
typedef void (^RAIBridgeTrampoline)(SEL selector, NSArray * _Nullable args);

@interface RAIMessageBridge : NSProxy

/// 创建包裹给定目标对象的桥。
- (instancetype)initWithTarget:(NSObject *)target;

/// 创建包裹目标的桥, 并附带消息转发回调。
- (instancetype)initWithTarget:(NSObject *)target
                     trampoline:(nullable RAIBridgeTrampoline)trampoline;

/// 被代理的真实目标。
@property (nonatomic, strong, readonly) NSObject *target;

@end

NS_ASSUME_NONNULL_END