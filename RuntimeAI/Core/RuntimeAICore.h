//
//  RuntimeAICore.h
//  RuntimeAI
//
//  调度层的核心单例: 统一承载「动作注册、意图判别、执行路由、结果聚合」。
//  意图判别 (改/调/查) 内聚在核心内部, 不拆分独立路由类。
//

#import <Foundation/Foundation.h>
#import "RAILLMProvider.h"

NS_ASSUME_NONNULL_BEGIN

/// 一次 runtime 指令的意图分类。
typedef NS_ENUM(NSInteger, RAIOpKind) {
    /// 改方法: 替换 / 交换实现或注入日志 (写操作, 有副作用)
    RAIOpKindModify = 0,
    /// 调方法: 执行一次调用并取回返回值 (执行操作)
    RAIOpKindInvoke = 1,
    /// 只读查询: describe / dump 类与方法信息 (无副作用)
    RAIOpKindQuery  = 2,
};

/// 单条已注册动作的描述与处理器。
typedef void (^RAIActionHandler)(NSDictionary * _Nonnull params, id _Nullable * _Nullable result, NSError * _Nullable * _Nullable error);

/// 统一结果回调。
typedef void (^RAICompletion)(
    id _Nullable result,
    NSError * _Nullable error
);

/**
 调度层核心。三块能力 (改 / 调 / 查 / 模型对话) 统一成"动作 + 参数"这一抽象,
 自然语言、脚本、手动点按钮最终都进入同一执行通道。
 */
@interface RuntimeAICore : NSObject

/// 全局共享实例。
+ (instancetype)shared NS_SWIFT_NAME(shared());

/// 大模型 Provider (可注入替换, 默认为空, 调用模型前必须指派)。
@property (nonatomic, strong, nullable) id<RAILLMProvider> llmProvider;

/// 本次判定的结果, 仅供界面展示。
@property (nonatomic, readonly) RAIOpKind lastOpKind;

// MARK: - 动作注册与执行

/// 注册一个可被调用的动作。动作名是唯一键, 重复注册覆盖旧 handler。
- (void)registerAction:(NSString *)name
               handler:(RAIActionHandler)handler;

/// 移除已注册的动作。
- (void)unregisterAction:(NSString *)name;

/// 按名字执行动作, 结果异步回传。
- (void)executeAction:(NSString *)name
               params:(NSDictionary *)params
           completion:(nullable RAICompletion)completion;

// MARK: - 意图判别与路由 (内聚在核心)

/// 判定指令方向并直接路由到 MethodSwizzler / MethodInvoker / LLM。
/// instruction 可带显式 type: @"modify" | @"invoke" | @"query", 否则按动词词法归类, 歧义兜底为只读查询。
- (void)classifyAndRoute:(NSDictionary *)instruction
              completion:(nullable RAICompletion)completion;

/// 把一段自然语言解释为动作调用 (内部经 classifyAndRoute 执行)。
- (void)handleNaturalLanguage:(NSString *)prompt
                   completion:(nullable RAICompletion)completion;

/// 通过 JSPatch 脚本 (defineClass) 修改/调用方法。脚本在隔离的 JS 引擎中执行。
/// 这是 "运行时修改方法" 的 JSPatch 主路径。
- (BOOL)evaluateJSPatchScript:(NSString *)script
                        error:(NSError * _Nullable __autoreleasing *)error;

/// 用大模型把自然语言意图生成 JSPatch 脚本并执行。生成前会注入目标类的方法列表作为上下文。
/// completion 的 result 为生成的脚本字符串 (执行成功时)。
- (void)applyAIIntent:(NSString *)intent
          targetClass:(NSString * _Nullable)targetClass
           completion:(nullable RAICompletion)completion;

// MARK: - 直通便捷方法

/// 直接调用目标类的方法 (自动归类为 RAIOpKindInvoke)。
- (void)invokeClass:(NSString *)className
           selector:(NSString *)selector
               args:(nullable NSArray *)args
         completion:(nullable RAICompletion)completion;

/// 数据清理: 还原所有未还原的 swizzle、关闭悬浮窗。
- (void)reset;

@end

NS_ASSUME_NONNULL_END