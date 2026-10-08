//
//  RAIMessageBridge.m
//  RuntimeAI
//

#import "RAIMessageBridge.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

@interface RAIMessageBridge ()
@property (nonatomic, strong, readwrite) NSObject *target;
@property (nonatomic, copy, nullable) RAIBridgeTrampoline trampoline;
@end

@implementation RAIMessageBridge

- (instancetype)initWithTarget:(NSObject *)target {
    return [self initWithTarget:target trampoline:nil];
}

- (instancetype)initWithTarget:(NSObject *)target trampoline:(RAIBridgeTrampoline)trampoline {
    if (target == nil) {
        return nil;
    }
    // NSProxy 不使用 [super init]
    self.target = target;
    self.trampoline = trampoline;
    return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [self.target methodSignatureForSelector:sel];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    SEL sel = invocation.selector;
    if (self.trampoline) {
        NSArray *args = [self _collectArgumentsForInvocation:invocation];
        self.trampoline(sel, args);
    }
    invocation.target = self.target;
    [invocation invoke];
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [self.target respondsToSelector:aSelector];
}

- (BOOL)isKindOfClass:(Class)aClass {
    return [self.target isKindOfClass:aClass];
}

- (BOOL)isMemberOfClass:(Class)aClass {
    return [self.target isMemberOfClass:aClass];
}

- (Class)class {
    return [self.target class];
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol {
    return [self.target conformsToProtocol:aProtocol];
}

- (BOOL)isProxy {
    return YES;
}

#pragma mark - 参数收集

- (NSArray *)_collectArgumentsForInvocation:(NSInvocation *)invocation {
    NSMethodSignature *sig = invocation.methodSignature;
    NSUInteger count = sig.numberOfArguments;
    if (count <= 2) return @[];
    NSMutableArray *args = [NSMutableArray array];
    for (NSUInteger i = 2; i < count; i++) {
        const char *type = [sig getArgumentTypeAtIndex:i];
        if (type && type[0] == '@') {
            __unsafe_unretained id arg = nil;
            [invocation getArgument:&arg atIndex:(NSInteger)i];
            [args addObject:arg ?: [NSNull null]];
        } else {
            [args addObject:[NSString stringWithFormat:@"<非对象参数 %s>", type ?: "?"]];
        }
    }
    return args;
}

@end

#pragma clang diagnostic pop