//
//  AIScriptGenerator.h
//  RuntimeAI
//
//  让大模型根据自然语言生成 JSPatch 脚本 (defineClass) 并执行。
//  核心价值: 在生成前用 runtime 枚举目标类的方法列表作为上下文注入, 并附上
//  JSPatch 语法规范与安全约束, 让模型输出可直接执行的纯脚本。
//

#import <Foundation/Foundation.h>
#import "RAILLMProvider.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^AIScriptResult)(NSString * _Nullable script, NSError * _Nullable error);

/**
 AI 驱动的 JSPatch 脚本生成器。
 使用方式:
   1. 配置 provider (同 RuntimeAICore.llmProvider 或独立注入)。
   2. 调 generateScriptFromPrompt: 传入 "改哪个类哪个方法, 改成什么"。
   3. 生成器扫描目标类方法 → 构建上下文 → 大模型产出 defineClass 脚本 → 校验 → 回传。
 */
@interface AIScriptGenerator : NSObject

/// 共享实例。
+ (instancetype)sharedInstance;

/// 大模型 Provider。若为 nil, 会自动读取 RuntimeAICore.shared.llmProvider。
@property (nonatomic, strong, nullable) id<RAILLMProvider> llmProvider;

/// 生成脚本但不执行。contextHint 可给目标类名/意图, 供上下文采集。
- (void)generateScriptForIntent:(NSString *)intent
                    targetClass:(NSString * _Nullable)targetClass
                     completion:(AIScriptResult)completion;

/// 生成并直接交给 JSPatch 引擎执行。
- (void)applyScriptForIntent:(NSString *)intent
                 targetClass:(NSString * _Nullable)targetClass
                  completion:(AIScriptResult)completion;

@end

NS_ASSUME_NONNULL_END