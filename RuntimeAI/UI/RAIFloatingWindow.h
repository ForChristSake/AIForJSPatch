//
//  RAIFloatingWindow.h
//  RuntimeAI
//
//  悬浮窗: 独立 UIWindow + 可拖拽悬浮球, 点开弹出控制台面板。
//  控制台收听 RuntimeAICore 的执行 (对话 / 调用 / 查询 / 修改)。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RAIFloatingWindow : NSObject

/// 全局唯一悬浮窗实例 (避免局部释放导致窗口闪没)。
+ (instancetype)sharedInstance;

/// 显示悬浮窗 (可在多个位置重复调用, 幂等)。
- (void)show;

/// 隐藏并释放悬浮窗。
- (void)hide;

/// 是否正在显示。
@property (nonatomic, readonly) BOOL isVisible;

@end

NS_ASSUME_NONNULL_END