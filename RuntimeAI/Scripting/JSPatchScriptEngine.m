//
//  JSPatchScriptEngine.m
//  RuntimeAI
//

#import "JSPatchScriptEngine.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import "JPEngine.h"

@implementation JSPatchScriptEngine {
    BOOL _started;
    NSString *_lastException;
}

+ (instancetype)sharedInstance {
    static JSPatchScriptEngine *_instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (void)start {
    if (_started) return;
    // 注册异常回调, 记录最近一条
    __weak typeof(self) wself = self;
    [JPEngine handleException:^(NSString *msg) {
        __strong typeof(wself) self = wself;
        self->_lastException = msg;
        if (self.exceptionHandler) self.exceptionHandler(msg);
    }];
    [JPEngine startEngine];
    _started = YES;
}

- (BOOL)isStarted {
    return _started;
}

- (BOOL)evaluateScript:(NSString *)script error:(NSError * _Nullable __autoreleasing *)error {
    if (!script.length) {
        if (error) *error = [NSError errorWithDomain:@"RuntimeAI.Script" code:300
            userInfo:@{NSLocalizedDescriptionKey: @"脚本内容为空"}];
        return NO;
    }
    [self start];
    _lastException = nil;
    [JPEngine evaluateScript:script];
    if (_lastException) {
        if (error) *error = [NSError errorWithDomain:@"RuntimeAI.Script" code:301
            userInfo:@{NSLocalizedDescriptionKey: _lastException}];
        return NO;
    }
    return YES;
}

- (BOOL)evaluateScriptFromPath:(NSString *)filePath error:(NSError * _Nullable __autoreleasing *)error {
    NSError *readErr = nil;
    NSString *script = [NSString stringWithContentsOfFile:filePath
                                                 encoding:NSUTF8StringEncoding
                                                    error:&readErr];
    if (!script) {
        if (error) *error = readErr ?: [NSError errorWithDomain:@"RuntimeAI.Script" code:302
            userInfo:@{NSLocalizedDescriptionKey: @"读取脚本文件失败"}];
        return NO;
    }
    return [self evaluateScript:script error:error];
}

- (BOOL)evaluateScriptFromResource:(NSString *)name error:(NSError * _Nullable __autoreleasing *)error {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:name ofType:@"js"];
    if (!path) {
        // 也允许 SDK 自身 bundle
        path = [[NSBundle bundleForClass:[self class]] pathForResource:name ofType:@"js"];
    }
    if (!path) {
        if (error) *error = [NSError errorWithDomain:@"RuntimeAI.Script" code:303
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"bundle 中找不到 %@.js", name]}];
        return NO;
    }
    return [self evaluateScriptFromPath:path error:error];
}

@end