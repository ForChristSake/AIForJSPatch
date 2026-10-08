//
//  MethodSwizzler.h
//  RuntimeAI
//
//  运行时方法修改器: 支持实例方法/类方法的方法交换, 并在内部记录原始 IMP 以便可逆还原。
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// 方法交换时提供的替换实现。参数与返回值完全放开, 由调用方按实际签名处理。
/// 传入: 原始目标 (self / 类), 原选择器。返回: 新实现应返回的值 (void 方法可返回 nil)。
typedef id _Nullable (^RAISwizzleBlock)(id _Nonnull target, SEL _Nonnull originalSelector, va_list args);

/**
 方法修改器。核心思路: 用 class_addMethod + method_setImplementation 做方法交换,
 保留一份原始 IMP, 支持 revert 统一还原, 避免污染宿主进程。
 */
@interface MethodSwizzler : NSObject

/// 交换一个实例方法的实现。成功返回 YES。
+ (BOOL)swizzleInstanceMethod:(SEL)original
                     onClass:(Class)cls
             withReplacement:(IMP)replacement
              storingOriginal:(IMP *_Nullable * _Nullable)origOut
                     error:(NSError * _Nullable * _Nullable)error;

/// 交换一个类方法 (meta 层) 的实现。
+ (BOOL)swizzleClassMethod:(SEL)original
                  onClass:(Class)cls
          withReplacement:(IMP)replacement
           storingOriginal:(IMP *_Nullable * _Nullable)origOut
                    error:(NSError * _Nullable * _Nullable)error;

/// 还原一个类上指定选择器的方法交换。返回是否还原成功。
+ (BOOL)revertSwizzleForClass:(Class)cls
                     selector:(SEL)sel;

/// 还原当前 SDK 记录过的所有交换。
+ (void)revertAll;

// MARK: - 便捷: 用 block 生成 IMP

/// 用 block 生成可供 method_setImplementation 使用的 IMP (需配合正确的调用约定)。
+ (IMP)impForBlock:(id)block;

@end

NS_ASSUME_NONNULL_END