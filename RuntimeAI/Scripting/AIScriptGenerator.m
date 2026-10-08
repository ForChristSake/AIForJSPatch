//
//  AIScriptGenerator.m
//  RuntimeAI
//

#import "AIScriptGenerator.h"
#import "JSPatchScriptEngine.h"
#import "RuntimeClassIndexer.h"
#import <objc/runtime.h>

// 注入给大模型的 JSPatch 语法规范 (system 层)。
static NSString *const kAISystemPrompt =
    @"你是一个 iOS Objective-C 运行时热更助手, 只负责把用户需求写成 "
    "JSPatch (defineClass) 脚本。\n"
    "JSPatch 脚本语法要求:\n"
    "1. 首行 require('要用的OC类名'), 多个类用逗号分隔。\n"
    "2. defineClass('类名', {实例方法定义}, {类方法定义可选})。\n"
    "3. 实例方法签名: OC 方法的冒号替换为下划线, 如 setTitle: 写成 setTitle_。\n"
    "4. 调原方法用 self.super.方法名()。必须有返回值时用 return。\n"
    "5. 优先采用下方 user 消息里提供的候选类与方法 (这些来自运行时真实索引, 名称可信), 禁止编造不存在的类名。仅当 user 消息没有给出任何候选时才自行判断。\n"
    "输出要求: 只输出纯 JavaScript 脚本本身, 禁止用 ``` 代码块包裹, "
    "禁止输出任何解释文字, 禁止加 console.log 之外的副作用全局语句。";

@implementation AIScriptGenerator

+ (instancetype)sharedInstance {
    static AIScriptGenerator *_instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (id<RAILLMProvider>)_effectiveProvider {
    if (self.llmProvider) return self.llmProvider;
    // 弱耦合读取 RuntimeAICore 默认 provider, 避免循环 import
    Class coreClass = NSClassFromString(@"RuntimeAICore");
    if (coreClass && [coreClass respondsToSelector:NSSelectorFromString(@"shared")]) {
        id core = [coreClass performSelector:NSSelectorFromString(@"shared")];
        id p = [core valueForKey:@"llmProvider"];
        if ([p conformsToProtocol:@protocol(RAILLMProvider)]) return p;
    }
    return nil;
}

#pragma mark - 公开方法

- (void)generateScriptForIntent:(NSString *)intent
                    targetClass:(NSString *)targetClass
                     completion:(AIScriptResult)completion {
    if (!completion) return;
    id<RAILLMProvider> provider = [self _effectiveProvider];
    if (!provider) {
        completion(nil, [NSError errorWithDomain:@"RuntimeAI.AIScript" code:400
            userInfo:@{NSLocalizedDescriptionKey: @"未配置大模型 Provider"}]);
        return;
    }

    // 1. 采集上下文: 有目标类 → 取其方法列表; 无目标类 → runtime 全量索引找候选
    NSMutableString *contextBlock = [NSMutableString string];
    if (targetClass.length) {
        NSString *methods = [self _contextForClass:targetClass];
        if (methods.length) {
            [contextBlock appendFormat:@"目标类: %@\n", targetClass];
            [contextBlock appendFormat:@"该类已存在的方法列表 (供你了解哪些方法可 hook): %@\n", methods];
        }
    } else {
        // 无目标类: runtime 索引器从意图中提取关键词, 匹配候选类与命中方法
        NSArray *candidates = [[RuntimeClassIndexer sharedInstance] findCandidatesForIntent:intent];
        if (candidates.count) {
            [contextBlock appendString:@"以下是运行时索引到的候选类 (按相关度排序, 类名与方法名均为真实存在):\n"];
            for (RAIIndexHit *hit in candidates) {
                NSArray *methods = [[RuntimeClassIndexer sharedInstance] methodNamesForClass:hit.className];
                NSString *methodStr = methods.count
                    ? [methods componentsJoinedByString:@", "]
                    : @"(空)";
                NSString *matchedStr = hit.matchedMethods.count
                    ? [hit.matchedMethods componentsJoinedByString:@", "]
                    : @"(无)";
                [contextBlock appendFormat:@"- %@ (命中方法: %@)\n  该类全部方法: %@\n",
                    hit.className, matchedStr, methodStr];
            }
        } else {
            [contextBlock appendString:@"运行时未检索到明显匹配的候选类。请基于通用 JSPatch 语法自行判断, 并优先使用系统 UIKit/Foundation 类名。\n"];
        }
    }

    // 2. 构建 user 消息
    NSMutableString *userMsg = [NSMutableString string];
    [userMsg appendFormat:@"用户需求: %@\n", intent ?: @""];
    [userMsg appendString:contextBlock];
    [userMsg appendString:@"请给出完整的 JSPatch 脚本。"];

    NSArray *messages = @[
        @{@"role": @"system",   @"content": kAISystemPrompt},
        @{@"role": @"user",     @"content": userMsg},
    ];

    // 3. 调模型
    [provider chatWithMessages:messages completion:^(NSString *reply, NSError *error) {
        if (error) { completion(nil, error); return; }
        if (!reply.length) {
            completion(nil, [NSError errorWithDomain:@"RuntimeAI.AIScript" code:401
                userInfo:@{NSLocalizedDescriptionKey: @"模型未返回脚本"}]);
            return;
        }
        NSString *clean = [self _cleanScript:reply];
        completion(clean, nil);
    }];
}

- (void)applyScriptForIntent:(NSString *)intent
                 targetClass:(NSString *)targetClass
                  completion:(AIScriptResult)completion {
    [self generateScriptForIntent:intent targetClass:targetClass completion:^(NSString *script, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSError *execErr = nil;
        BOOL ok = [[JSPatchScriptEngine sharedInstance] evaluateScript:script error:&execErr];
        if (completion) {
            if (ok) completion(script, nil);
            else     completion(nil, execErr ?: [NSError errorWithDomain:@"RuntimeAI.AIScript" code:402
                userInfo:@{NSLocalizedDescriptionKey: @"脚本执行失败"}]);
        }
    }];
}

#pragma mark - 上下文采集

/// 枚举目标类的方法列表作为上下文。
- (NSString *)_contextForClass:(NSString *)className {
    if (!className.length) return @"";
    Class cls = NSClassFromString(className);
    if (!cls) return @"(未在运行时找到该类)";

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        Method m = list[i];
        [names addObject:NSStringFromSelector(method_getName(m))];
    }
    free(list);

    if (count == 0) return @"(该类无实例方法)";
    return [names componentsJoinedByString:@", "];
}

/// 去掉模型可能包裹的 markdown 代码块, 只留 JS。
- (NSString *)_cleanScript:(NSString *)raw {
    NSString *s = raw;
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange start = [s rangeOfString:@"```"];
    if (start.location != NSNotFound) {
        NSRange restStart = NSMakeRange(start.location + start.length, s.length - start.location - start.length);
        NSRange end = [s rangeOfString:@"```" options:0 range:restStart];
        NSRange codeStart = [s rangeOfString:@"\n" options:0 range:restStart];
        // 处理 [``` 或 ```javascript] 开头的代码块
        NSUInteger from = codeStart.location != NSNotFound && codeStart.location >= start.location
                        ? codeStart.location + 1 : start.location + start.length;
        NSString *inner = end.location != NSNotFound
                        ? [s substringWithRange:NSMakeRange(from, end.location - from)]
                        : [s substringFromIndex:from];
        return [inner stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return s;
}

@end