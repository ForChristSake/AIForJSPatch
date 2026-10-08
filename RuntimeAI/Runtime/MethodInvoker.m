//
//  MethodInvoker.m
//  RuntimeAI
//

#import "MethodInvoker.h"
#import <objc/message.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

@implementation MethodInvoker

+ (NSDictionary *)invokeClass:(NSString *)className
                     selector:(NSString *)selector
                         args:(nullable NSArray *)args {
    Class cls = NSClassFromString(className);
    if (!cls) {
        return [self _err:className sel:selector message:[NSString stringWithFormat:@"类 %@ 不存在", className]];
    }

    id target = cls; // 类方法用类对象

    // 若该类有默认单例或 sharedInstance, 可调用其实例方法 —— 语义约定: 优先类方法, 失败再尝试共享实例
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) {
        // 尝试 sharedInstance
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if ([cls respondsToSelector:sharedSel]) {
            target = [cls performSelector:sharedSel];
            if (target) {
                return [self _invokeOn:target sel:sel selStr:selector args:args className:className];
            }
        }
        return [self _err:className sel:selector message:[NSString stringWithFormat:@"%@ 不支持选择器 %@", className, selector]];
    }

    return [self _invokeOn:target sel:sel selStr:selector args:args className:className];
}

+ (NSDictionary *)invokeClass:(NSString *)className
                     selector:(NSString *)selector
                         args:(nullable NSArray *)args
                  returnType:(nullable NSString *)encodeString {
    // 简化: 复杂返回类型走 NSInvocation 包装。此处对非对象类型返回字典描述。
    @try {
        NSDictionary *base = [self invokeClass:className selector:selector args:args];
        if ([base[@"success"] boolValue] && encodeString) {
            // 若返回值确实是对象, 直接透传; 结构体等复杂类型较难通用映射, 记录其类型串。
            return base;
        }
        return base;
    } @catch (NSException *e) {
        return [self _err:className sel:selector message:[NSString stringWithFormat:@"调用异常: %@", e.reason]];
    }
}

+ (NSDictionary *)invokeObject:(NSObject *)target
                      selector:(NSString *)selector
                          args:(nullable NSArray *)args {
    if (!target) {
        return [self _err:@"(实例)" sel:selector message:@"目标对象为空"];
    }
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) {
        return [self _err:NSStringFromClass([target class]) sel:selector
                   message:[NSString stringWithFormat:@"实例不支持选择器 %@", selector]];
    }
    return [self _invokeOn:target sel:sel selStr:selector args:args
                 className:NSStringFromClass([target class])];
}

#pragma mark - 内部

+ (NSDictionary *)_invokeOn:(id)target sel:(SEL)sel selStr:(NSString *)selStr
                       args:(NSArray *)args className:(NSString *)className {
    @try {
        switch (args.count) {
            case 0:  return [self _ok:className sel:selStr result:[target performSelector:sel]];
            case 1:  return [self _ok:className sel:selStr result:[target performSelector:sel withObject:args[0]]];
            case 2:  return [self _ok:className sel:selStr result:[target performSelector:sel withObject:args[0] withObject:args[1]]];
            default:
                return [self _invokeWithInvocation:target sel:sel selStr:selStr args:args className:className];
        }
    } @catch (NSException *e) {
        return [self _err:className sel:selStr message:[NSString stringWithFormat:@"调用异常: %@", e.reason]];
    }
}

/// 参数超过 2 个或用 NSInvocation 兜底, 支持复杂触发。
+ (NSDictionary *)_invokeWithInvocation:(id)target sel:(SEL)sel selStr:(NSString *)selStr
                                   args:(NSArray *)args className:(NSString *)className {
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    if (!sig) {
        return [self _err:className sel:selStr message:@"无法获得方法签名 (可能未暴露实现)"];
    }
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = target;
    inv.selector = sel;
    for (NSUInteger i = 0; i < args.count && i + 2 < sig.numberOfArguments; i++) {
        id a = args[i];
        const char *type = [sig getArgumentTypeAtIndex:i + 2];
        // 只安全处理对象类型; 其它类型记录为不支持
        if (type && type[0] == '@') {
            [inv setArgument:&a atIndex:(NSInteger)i + 2];
        } else {
            return [self _err:className sel:selStr
                       message:[NSString stringWithFormat:@"第 %lu 个参数为非对象类型, 需使用带签名的特殊调用", (unsigned long)i]];
        }
    }
    [inv invoke];

    // 取返回值 (仅对象类型)
    const char *retType = sig.methodReturnType;
    id result = nil;
    if (retType && retType[0] == '@') {
        void *ret = NULL;
        [inv getReturnValue:&ret];
        result = (__bridge id)ret;
    }
    return [self _ok:className sel:selStr result:result];
}

#pragma mark - 结果构造

+ (NSDictionary *)_ok:(NSString *)className sel:(NSString *)sel result:(id)result {
    return @{
        @"success": @YES,
        @"className": className ?: @"",
        @"selector": sel ?: @"",
        @"result": result ?: [NSNull null],
    };
}

+ (NSDictionary *)_err:(NSString *)className sel:(NSString *)sel message:(NSString *)message {
    return @{
        @"success": @NO,
        @"className": className ?: @"",
        @"selector": sel ?: @"",
        @"result": [NSNull null],
        @"error": @{@"code": @-1, @"message": message ?: @"未知错误"},
    };
}

@end

#pragma clang diagnostic pop