//
//  RuntimeAI.h
//  RuntimeAI — 统一的 SDK 导入头
//
//  说明: RuntimeAI 是一个面向 iOS 开发与内测调试的嵌入式 SDK, 在进程内打通
//  「调用大模型、运行时修改方法、运行时调用方法」三项能力, 并以悬浮窗作为交互入口。
//
//  定位约束: 本 SDK 仅用于 Debug / 内测调试, 不应随正式包上架 (规避 Apple Guideline 2.5.2)。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Core — 调度与意图判别
#import "RuntimeAICore.h"

// Runtime — 运行时修改 / 调用 / 转发
#import "MethodSwizzler.h"
#import "MethodInvoker.h"
#import "RAIMessageBridge.h"

// Scripting — JSPatch 脚本引擎 (defineClass 改方法)
#import "JSPatchScriptEngine.h"

// Scripting — AI 驱动的 JSPatch 脚本生成器 (自然语言 → 脚本 → 执行)
#import "AIScriptGenerator.h"

// Scripting — 运行时类/方法索引器 (无目标类时自动检索候选)
#import "RuntimeClassIndexer.h"

// LLM — 大模型抽象与参考实现
#import "RAILLMProvider.h"
#import "RAIOpenAICompatibleProvider.h"

// UI — 悬浮窗与控制台
#import "RAIFloatingWindow.h"

//! Project version number for RuntimeAI.
FOUNDATION_EXPORT double RuntimeAIVersionNumber;

//! Project version string for RuntimeAI.
FOUNDATION_EXPORT const unsigned char RuntimeAIVersionString[];