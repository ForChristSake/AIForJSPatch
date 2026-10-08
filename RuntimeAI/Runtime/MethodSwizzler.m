//
//  MethodSwizzler.m
//  RuntimeAI
//

#import "MethodSwizzler.h"

/// 记录一次交换的原始信息, 用于可逆还原。
typedef struct RAISwizzleRecord {
    __unsafe_unretained Class cls;
    SEL sel;
    IMP originalIMP;
    BOOL isClassMethod;
} RAISwizzleRecord;

@implementation MethodSwizzler {
    // 记录表由模块内部维护
    static NSMutableArray *_records;
    static NSLock *_lock;
}

+ (void)initialize {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _records = [NSMutableArray array];
        _lock = [[NSLock alloc] init];
    });
}

#pragma mark - 交换

+ (BOOL)swizzleInstanceMethod:(SEL)original onClass:(Class)cls
              withReplacement:(IMP)replacement
               storingOriginal:(IMP *_Nullable *)origOut
                        error:(NSError * _Nullable __autoreleasing *)error {
    return [self _swizzleMethod:original
                        onClass:cls
                        isClass:NO
                withReplacement:replacement
                 storingOriginal:origOut
                          error:error];
}

+ (BOOL)swizzleClassMethod:(SEL)original onClass:(Class)cls
           withReplacement:(IMP)replacement
           storingOriginal:(IMP *_Nullable *)origOut
                    error:(NSError * _Nullable __autoreleasing *)error {
    return [self _swizzleMethod:original
                        onClass:cls
                        isClass:YES
                withReplacement:replacement
                 storingOriginal:origOut
                          error:error];
}

+ (BOOL)_swizzleMethod:(SEL)sel onClass:(Class)cls isClass:(BOOL)isClass
       withReplacement:(IMP)replacement
        storingOriginal:(IMP *_Nullable *)origOut
                 error:(NSError * _Nullable __autoreleasing *)error {
    if (!sel || !cls || !replacement) {
        if (error) *error = [NSError errorWithDomain:@"RuntimeAI.MethodSwizzler"
                                                code:100
                                            userInfo:@{NSLocalizedDescriptionKey: @"参数不完整 (cls/sel/replacement 缺失)"}];
        return NO;
    }

    Class targetClass = isClass ? object_getClass(cls) : cls;
    Method originalMethod = class_getInstanceMethod(targetClass, sel);
    if (!originalMethod) {
        targetClass = cls; // 类方法回退尝试
        originalMethod = class_getInstanceMethod(targetClass, sel);
        if (!originalMethod) {
            if (error) *error = [NSError errorWithDomain:@"RuntimeAI.MethodSwizzler"
                                                    code:101
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"未找到选择器 %@ 的方法", NSStringFromSelector(sel)]}];
            return NO;
        }
    }

    IMP originalIMP = method_getImplementation(originalMethod);
    if (origOut) *origOut = originalIMP;

    // 仍用原选择器, 仅替换实现; 避免交换先后顺序影响到其它调用方。
    method_setImplementation(originalMethod, replacement);

    [_lock lock];
    RAISwizzleRecord rec;
    rec.cls = cls;
    rec.sel = sel;
    rec.originalIMP = originalIMP;
    rec.isClassMethod = isClass;
    [_records addObject:
        [NSValue valueWithBytes:&rec objCType:@encode(RAISwizzleRecord)]];
    [_lock unlock];

    return YES;
}

#pragma mark - 还原

+ (BOOL)revertSwizzleForClass:(Class)cls selector:(SEL)sel {
    __block BOOL found = NO;
    [_lock lock];
    NSMutableArray *toRemove = [NSMutableArray array];
    for (NSValue *v in [_records copy]) {
        RAISwizzleRecord rec;
        [v getValue:&rec];
        if (rec.cls == cls && rec.sel == sel) {
            Class m = rec.isClassMethod ? object_getClass(rec.cls) : rec.cls;
            Method method = class_getInstanceMethod(m, rec.sel);
            if (method) method_setImplementation(method, rec.originalIMP);
            [toRemove addObject:v];
            found = YES;
        }
    }
    if (found) [_records removeObjectsInArray:toRemove];
    [_lock unlock];
    return found;
}

+ (void)revertAll {
    [_lock lock];
    for (NSValue *v in [_records copy]) {
        RAISwizzleRecord rec;
        [v getValue:&rec];
        Class m = rec.isClassMethod ? object_getClass(rec.cls) : rec.cls;
        Method method = class_getInstanceMethod(m, rec.sel);
        if (method) method_setImplementation(method, rec.originalIMP);
    }
    [_records removeAllObjects];
    [_lock unlock];
}

#pragma mark - IMP from block

+ (IMP)impForBlock:(id)block {
    return imp_implementationWithBlock(block);
}

@end