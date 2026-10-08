//
//  JSPatchScriptEngine.h
//  RuntimeAI
//
//  JSPatch 脚本引擎适配层: 封装 JPEngine, 提供 defineClass 脚本的加载与执行。
//  让 "运行时修改方法" 真正走 JSPatch 脚本, 而非纯 OC swizzle。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^JSScriptExceptionHandler)(NSString *message);

/// 基于 JSPatch (JPEngine) 的脚本执行引擎。
@interface JSPatchScriptEngine : NSObject

/// 全局唯一的脚本引擎。
+ (instancetype)sharedInstance;

/// 启动 JSPatch 引擎 (幂等, 底层 startEngine 只执行一次)。
- (void)start;

/// 是否已成功启动。
@property (nonatomic, readonly) BOOL isStarted;

/// 脚本执行异常回调 (可选, 用于浮出错误)。
@property (nonatomic, copy, nullable) JSScriptExceptionHandler exceptionHandler;

/// 从字符串执行一段 JS 脚本 (内部含 defineClass 时即改写方法)。
- (BOOL)evaluateScript:(NSString *)script
               error:(NSError * _Nullable __autoreleasing *)error;

/// 从指定文件路径执行 JS 脚本。
- (BOOL)evaluateScriptFromPath:(NSString *)filePath
                        error:(NSError * _Nullable __autoreleasing *)error;

/// 从 main bundle 中名为 name、类型 js 的资源执行脚本。
- (BOOL)evaluateScriptFromResource:(NSString *)name
                            error:(NSError * _Nullable __autoreleasing *)error;

@end

NS_ASSUME_NONNULL_END