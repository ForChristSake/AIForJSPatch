//
//  RuntimeClassIndexer.m
//  RuntimeAI
//

#import "RuntimeClassIndexer.h"
#import <objc/runtime.h>

// 已知系统框架前缀, 默认从结果中排除, 避免把整个 UIKit/Foundation 灌给模型。
static NSSet<NSString *> *FrameworkPrefixes(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[
            @"NS", @"UI", @"CG", @"CA", @"CF", @"CL", @"AV", @"Core",
            @"_", @"__", @"OS", @"MV", @"MF", @"AB", @"AD", @"AS",
        ]];
    });
    return set;
}

@implementation RAIIndexHit
@end

@interface RuntimeClassIndexer ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *index;
@property (nonatomic, strong) NSArray<NSString *> *allClassNames;
@end

@implementation RuntimeClassIndexer

+ (instancetype)sharedInstance {
    static RuntimeClassIndexer *_instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _instance = [[self alloc] init];
        _instance.index = [NSMutableDictionary dictionary];
    });
    return _instance;
}

- (void)rebuildIndex {
    [self.index removeAllObjects];

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:classCount];

    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        const char *name = class_getName(cls);
        if (!name) continue;
        NSString *clsName = @(name);
        [names addObject:clsName];

        NSMutableArray<NSString *> *methods = [NSMutableArray array];

        // 实例方法
        unsigned int instCount = 0;
        Method *inst = class_copyMethodList(cls, &instCount);
        for (unsigned int j = 0; j < instCount; j++) {
            [methods addObject:NSStringFromSelector(method_getName(inst[j]))];
        }
        free(inst);

        // 类方法 (元类上的实例方法)
        Class meta = objc_getMetaClass(name);
        unsigned int metaCount = 0;
        Method *metaList = class_copyMethodList(meta, &metaCount);
        for (unsigned int j = 0; j < metaCount; j++) {
            [methods addObject:NSStringFromSelector(method_getName(metaList[j]))];
        }
        free(metaList);

        self.index[clsName] = [methods copy];
    }
    free(classes);

    self.allClassNames = [names copy];
}

- (NSArray<RAIIndexHit *> *)findCandidatesForIntent:(NSString *)intent {
    if (!self.allClassNames) [self rebuildIndex];
    if (!intent.length) return @[];

    // 1. 从意图中提取候选 token: 小写字母数字串 + 直接包含的类名字串
    NSMutableSet<NSString *> *tokens = [NSMutableSet set];
    NSCharacterSet *lower = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"];
    NSScanner *scanner = [NSScanner scannerWithString:intent];
    while (!scanner.isAtEnd) {
        NSString *token = nil;
        [scanner scanCharactersFromSet:lower intoString:&token];
        if (token.length >= 2) [tokens addObject:token.lowercaseString];
        [scanner scanCharactersFromSet:[lower invertedSet] intoString:NULL];
    }

    // 2. 对每个类打分匹配
    NSMutableArray<RAIIndexHit *> *hits = [NSMutableArray array];
    for (NSString *clsName in self.allClassNames) {
        // 定义 App 类过滤: 排除系统框架前缀
        BOOL isFramework = NO;
        for (NSString *pfx in FrameworkPrefixes()) {
            if ([clsName hasPrefix:pfx]) { isFramework = YES; break; }
        }
        if (isFramework) continue;

        NSString *lowCls = clsName.lowercaseString;
        NSString *lowIntent = intent.lowercaseString;

        NSInteger score = 0;
        // 意图里直接出现完整类名 → 最高分
        if (lowIntent.length && [lowIntent containsString:lowCls]) {
            score += 100;
        }
        // token 匹配类名片段
        for (NSString *tok in tokens) {
            if ([lowCls containsString:tok]) score += 20;
        }

        NSMutableArray<NSString *> *matchedMethods = [NSMutableArray array];
        NSInteger methodHit = 0;
        NSArray<NSString *> *methods = self.index[clsName];
        for (NSString *sel in methods) {
            NSString *lowSel = sel.lowercaseString;
            BOOL hit = NO;
            for (NSString *tok in tokens) {
                if (tok.length >= 3 && [lowSel containsString:tok]) { hit = YES; methodHit++; break; }
            }
            if (!hit && lowIntent.length && [lowSel containsString:lowIntent]) {
                hit = YES; methodHit++;
            }
            if (hit) {
                [matchedMethods addObject:sel];
                if (matchedMethods.count >= 8) break; // 至多给模型 8 个命中方法作参考
            }
        }
        score += methodHit * 10;

        if (score > 0) {
            RAIIndexHit *h = [RAIIndexHit new];
            h.className = clsName;
            h.matchedMethods = [matchedMethods copy];
            h.score = score;
            [hits addObject:h];
        }
    }

    // 3. 按得分降序, 返回 top 6, 使上下文保持精简
    [hits sortUsingComparator:^NSComparisonResult(RAIIndexHit *a, RAIIndexHit *b) {
        return b.score > a.score ? NSOrderedAscending : (b.score < a.score ? NSOrderedDescending : NSOrderedSame);
    }];
    if (hits.count > 6) {
        hits = [[hits subarrayWithRange:NSMakeRange(0, 6)] mutableCopy];
    }
    return hits;
}

- (NSArray<NSString *> *)methodNamesForClass:(NSString *)className {
    if (!self.allClassNames) [self rebuildIndex];
    return self.index[className] ?: @[];
}

@end