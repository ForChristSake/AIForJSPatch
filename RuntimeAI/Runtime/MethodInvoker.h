//
//  MethodInvoker.h
//  RuntimeAI
//
//  运行时方法调用器: 按 类名 + 选择器 反射调用方法, 返回可 JSON 化的结果字典。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 方法调用器 (只读 + 只执行, 不做永久修改)。
 返回统一结构:
 {
   success: BOOL,
   className: NSString,
   selector: NSString,
   result: 调用返回值 (可 JSON 化) 或 nil,
   error: {code, message}  当 success 为 NO 时
 }
 */
@interface MethodInvoker : NSObject

/// 最简调用: 类方法或实例方法均可, 参数仅支持基本类型 (NSString/NSNumber/NSArray/NSDictionary/NSNull)。
+ (NSDictionary *)invokeClass:(NSString *)className
                     selector:(NSString *)selector
                         args:(nullable NSArray *)args;

/// 带显式 @encode 返回类型签名的调用, 用于处理结构体等复杂返回 (此时返回 result 为 NSData 包装或字典描述)。
+ (NSDictionary *)invokeClass:(NSString *)className
                     selector:(NSString *)selector
                         args:(nullable NSArray *)args
                  returnType:(nullable NSString *)encodeString;

/// 调用给定实例的一个方法。
+ (NSDictionary *)invokeObject:(NSObject *)target
                      selector:(NSString *)selector
                          args:(nullable NSArray *)args;

@end

NS_ASSUME_NONNULL_END