//
//  RuntimeAICore.m
//  RuntimeAI
//

#import "RuntimeAICore.h"
#import "MethodSwizzler.h"
#import "MethodInvoker.h"
#import "JSPatchScriptEngine.h"
#import "AIScriptGenerator.h"

// 词法判别用的动词特征表 (可扩展)
static NSArray<NSString *> *ModifyKeywords(void) {
    return @[@"替换", @"覆盖", @"注入", @"日志", @"hook", @"swizzle", @"替换方法",
             @"modify", @"replace", @"override", @"inject", @"log"];
}
static NSArray<NSString *> *InvokeKeywords(void) {
    return @[@"调用", @"执行", @"运行", @"invoke", @"call", @"execute", @"run", @"get"];
}

@implementation RuntimeAICore {
    NSMutableDictionary<NSString *, RAIActionHandler> *_registry;
    NSMutableArray<NSString *> *_logBuffer;
}

+ (instancetype)shared {
    static RuntimeAICore *_instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _registry = [NSMutableDictionary dictionary];
        _logBuffer = [NSMutableArray array];
        _lastOpKind = RAIOpKindQuery; // 默认只读
    }
    return self;
}

#pragma mark - 动作注册 / 执行

- (void)registerAction:(NSString *)name handler:(RAIActionHandler)handler {
    if (!name) return;
    _registry[name] = handler ?: ^(NSDictionary *params, id *result, NSError **error){};
}

- (void)unregisterAction:(NSString *)name {
    if (!name) return;
    [_registry removeObjectForKey:name];
}

- (void)executeAction:(NSString *)name
               params:(NSDictionary *)params
           completion:(RAICompletion)completion {
    RAIActionHandler handler = _registry[name];
    if (!handler) {
        if (completion) completion(nil, [self _error:-1001 message:[NSString stringWithFormat:@"未注册的动作: %@", name]]);
        return;
    }
    id result = nil;
    NSError *error = nil;
    handler(params ?: @{}, &result, &error);
    if (completion) completion(result, error);
}

#pragma mark - 意图判别与路由 (内聚在核心)

- (void)classifyAndRoute:(NSDictionary *)instruction
              completion:(RAICompletion)completion {
    if (!instruction) {
        if (completion) completion(nil, [self _error:-1002 message:@"指令为空"]);
        return;
    }

    RAIOpKind kind = [self _classify:instruction];
    _lastOpKind = kind;

    switch (kind) {
        case RAIOpKindModify:
            [self _routeModify:instruction completion:completion];
            break;
        case RAIOpKindInvoke:
            [self _routeInvoke:instruction completion:completion];
            break;
        case RAIOpKindQuery:
            [self _routeQuery:instruction completion:completion];
            break;
    }
}

/// 三层判定: ① 显式 type 声明 ② 词法特征 ③ 兜底 query。
- (RAIOpKind)_classify:(NSDictionary *)instruction {
    // ① 显式声明
    NSString *type = instruction[@"type"];
    if (type) {
        if ([type isKindOfClass:[NSString class]]) {
            NSString *t = [type lowercaseString];
            if ([t containsString:@"modify"] || [t containsString:@"改"] || [t containsString:@"替换"]) return RAIOpKindModify;
            if ([t containsString:@"invoke"] || [t containsString:@"调"] || [t containsString:@"执行"]) return RAIOpKindInvoke;
            if ([t containsString:@"query"] || [t containsString:@"查"] || [t containsString:@"describe"]) return RAIOpKindQuery;
        }
    }

    // ② 词法特征
    NSString *action = instruction[@"action"];
    NSString *verb = instruction[@"verb"];
    NSString *text = [NSString stringWithFormat:@"%@ %@ %@",
                      action ?: @"", verb ?: @"", instruction[@"text"] ?: @""];

    for (NSString *kw in ModifyKeywords()) {
        if ([text localizedCaseInsensitiveContainsString:kw]) return RAIOpKindModify;
    }
    for (NSString *kw in InvokeKeywords()) {
        if ([text localizedCaseInsensitiveContainsString:kw]) return RAIOpKindInvoke;
    }

    // ③ 兜底
    return RAIOpKindQuery;
}

/// 路由到方法修改器: 优先 JSPatch 脚本 (defineClass), 否则回退 OC swizzle。
- (void)_routeModify:(NSDictionary *)instruction completion:(RAICompletion)completion {
    // JSPatch 主路径: 指令携带脚本内容或脚本文件路径时, 用它驱动方法修改。
    NSString *script = instruction[@"script"] ?: instruction[@"js"];
    NSString *path   = instruction[@"scriptPath"];
    if (script.length || path.length) {
        NSError *err = nil;
        BOOL ok;
        if (script.length) {
            ok = [[JSPatchScriptEngine sharedInstance] evaluateScript:script error:&err];
        } else {
            ok = [[JSPatchScriptEngine sharedInstance] evaluateScriptFromPath:path error:&err];
        }
        if (completion) {
            if (ok) completion(@{@"scriptApplied": @YES, @"source": script.length ? @"string" : @"path"}, nil);
            else     completion(nil, err ?: [self _error:-1010 message:@"JSPatch 脚本执行失败"]);
        }
        return;
    }

    // 回退路径: 纯 OC swizzle (无脚本时的降级方案)
    NSString *clsName = instruction[@"className"];
    NSString *selStr  = instruction[@"selector"];
    // 新实现来自 instruction[@"implementation"] (一个 block) 或为打日志注入。
    id implBlock = instruction[@"implementation"];

    if (!clsName || !selStr) {
        if (completion) completion(nil, [self _error:-1003 message:@"modify 需要 className + selector 或 script"]);
        return;
    }
    Class cls = NSClassFromString(clsName);
    if (!cls) {
        if (completion) completion(nil, [self _error:-1004 message:[NSString stringWithFormat:@"类不存在: %@", clsName]]);
        return;
    }

    SEL sel = NSSelectorFromString(selStr);
    IMP imp = implBlock ? [MethodSwizzler impForBlock:implBlock]
                        : [MethodSwizzler impForBlock:^(id target, SEL originalSel, ...) {
                            NSLog(@"[RuntimeAI] swizzle-hook: %@ %@", target, NSStringFromSelector(originalSel));
                            return nil;
                        }];

    NSError *error = nil;
    BOOL ok = [MethodSwizzler swizzleInstanceMethod:sel
                                            onClass:cls
                                    withReplacement:imp
                                     storingOriginal:NULL
                                              error:&error];
    if (completion) {
        if (ok) completion(@{@"swizzled": @YES, @"className": clsName, @"selector": selStr}, nil);
        else     completion(nil, error ?: [self _error:-1005 message:@"swizzle 失败"]);
    }
}

/// 路由到方法调用器。
- (void)_routeInvoke:(NSDictionary *)instruction completion:(RAICompletion)completion {
    NSString *clsName = instruction[@"className"];
    NSString *selStr  = instruction[@"selector"];
    NSArray  *args    = instruction[@"args"];
    if (!clsName || !selStr) {
        if (completion) completion(nil, [self _error:-1006 message:@"invoke 需要 className + selector"]);
        return;
    }
    NSDictionary *result = [MethodInvoker invokeClass:clsName selector:selStr args:args];
    if (completion) {
        if ([result[@"success"] boolValue]) completion(result[@"result"], nil);
        else completion(nil, [self _error:-1007 message:result[@"error"][@"message"]]);
    }
}

/// 路由到只读查询。
- (void)_routeQuery:(NSDictionary *)instruction completion:(RAICompletion)completion {
    NSString *clsName = instruction[@"className"];
    if (!clsName) {
        if (completion) completion(nil, [self _error:-1008 message:@"query 需要 className"]);
        return;
    }
    Class cls = NSClassFromString(clsName);
    if (!cls) {
        if (completion) completion(nil, [self _error:-1004 message:[NSString stringWithFormat:@"类不存在: %@", clsName]]);
        return;
    }
    NSMutableArray *methods = [NSMutableArray array];
    unsigned int mc = 0;
    Method *list = class_copyMethodList(cls, &mc);
    for (unsigned int i = 0; i < mc; i++) {
        Method m = list[i];
        [methods addObject:NSStringFromSelector(method_getName(m))];
    }
    free(list);
    if (completion) completion(@{@"className": clsName, @"methods": methods}, nil);
}

#pragma mark - 自然语言入口

- (void)handleNaturalLanguage:(NSString *)prompt completion:(RAICompletion)completion {
    if (!prompt.length) {
        if (completion) completion(nil, [self _error:-1009 message:@"prompt 为空"]);
        return;
    }
    // 简化实现: 若无显式结构, 先尝试词法归类; 若含 "问/查证/对话" 等则走模型。
    NSDictionary *instr = @{@"text": prompt};
    RAIOpKind kind = [self _classify:instr];
    if (kind == RAIOpKindQuery && self.llmProvider) {
        // 无明确 runtime 语义时, 视为通用对话
        __weak typeof(self) wself = self;
        [self.llmProvider chatWithMessages:@[
            @{@"role": @"user", @"content": prompt}
        ] completion:^(NSString *reply, NSError *error) {
            __strong typeof(wself) self = wself;
            if (completion) completion(reply, error);
        }];
        return;
    }
    [self classifyAndRoute:instr completion:completion];
}

#pragma mark - 便捷方法

- (void)applyAIIntent:(NSString *)intent
          targetClass:(NSString *)targetClass
           completion:(RAICompletion)completion {
    // 交给生成器: 它负责注入目标类上下文、调大模型生成脚本并执行。
    [[AIScriptGenerator sharedInstance] applyScriptForIntent:intent targetClass:targetClass
                                                 completion:^(NSString *script, NSError *error) {
        if (completion) completion(script, error);
    }];
}

- (BOOL)evaluateJSPatchScript:(NSString *)script
                        error:(NSError * _Nullable __autoreleasing *)error {
    // 独立入口: 直接执行一段 JSPatch 脚本 (defineClass 改写方法)。
    return [[JSPatchScriptEngine sharedInstance] evaluateScript:script error:error];
}

- (void)invokeClass:(NSString *)className
           selector:(NSString *)selector
               args:(NSArray *)args
         completion:(RAICompletion)completion {
    [self classifyAndRoute:@{
        @"type": @"invoke",
        @"className": className ?: @"",
        @"selector": selector ?: @"",
        @"args": args ?: @[],
    } completion:completion];
}

- (void)reset {
    [MethodSwizzler revertAll];
    [_registry removeAllObjects];
    _lastOpKind = RAIOpKindQuery;
}

#pragma mark - 工具

- (NSError *)_error:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:@"RuntimeAI.Core" code:code
        userInfo:@{NSLocalizedDescriptionKey: message ?: @"未知错误"}];
}

@end