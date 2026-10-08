//
//  RuntimeClassIndexer.h
//  RuntimeAI
//
//  运行时类/方法索引器: 遍历当前 App 全部已注册的类与方法建立索引,
//  从一段自然语言意图中提取关键词, 匹配出该 hook/调用哪些类与方法。
//  作为大模型生成 JSPatch 脚本的上下文来源 (代替 RAG, 零向量依赖)。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 一个候选匹配结果: 命中某个类, 以及该类中被意图命中的方法名。
@interface RAIIndexHit : NSObject
/// 命中的类名
@property (nonatomic, copy) NSString *className;
/// 该类中被命中的方法名数组 (不含最终注入的全部方法, 仅标记匹配原因)
@property (nonatomic, copy) NSArray<NSString *> *matchedMethods;
/// 匹配得分 (越高越优先)
@property (nonatomic, assign) NSInteger score;
@end

/**
 类/方法运行时索引。用于在用户未显式给出目标类时, 把自然语言意图
 映射到真实存在的类与方法上。
 */
@interface RuntimeClassIndexer : NSObject

/// 共享单例。
+ (instancetype)sharedInstance;

/// 清空缓存并重新扫描全部已注册类与方法 (App 启动后/类装载后可调用一次)。
- (void)rebuildIndex;

/// 根据意图关键词, 返回按得分降序的候选类。忽略系统框架噪音类可选。
- (NSArray<RAIIndexHit *> *)findCandidatesForIntent:(NSString *)intent;

/// 直接取某类的全部实例方法名列表 (供注入上下文)。
- (NSArray<NSString *> *)methodNamesForClass:(NSString *)className;

@end

NS_ASSUME_NONNULL_END