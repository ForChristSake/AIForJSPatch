/*
 * demo_patch.js
 * RuntimeAI — JSPatch 方法修改示例脚本
 *
 * 通过 defineClass 在运行时改写一个 Objective-C 类的方法。
 * 用 self.super.原方法() 保留原逻辑, 在其上叠加新行为。
 *
 * 执行方式 (OC):
 *   NSError *err = nil;
 *   [[RuntimeAICore shared] evaluateJSPatchScript:@"require('UIViewController'); ...(本文件内容)..."]
 *   或 [[JSPatchScriptEngine sharedInstance] evaluateScriptFromResource:@"demo_patch" error:&err];
 */

// 导入要引用的原生类
require('UIViewController')

// 改写 UIViewController 的 viewDidLoad: 原逻辑照常执行, 追加一条日志
defineClass('UIViewController', {
    viewDidLoad: function() {
        self.super.viewDidLoad()
        console.log('[JSPatch] UIViewController.viewDidLoad was called:', self.description())
    }
})

// 有返回值的方法: 拦截并改返回值
// defineClass('MyService', {
//     fetchTitle: function() {
//         var original = self.super.fetchTitle()
//         return '[SDK前缀]' + original
//     }
// })

// 类方法也能改 (第二参传类方法定义): 
// defineClass('UIApplication', { }, {
//     sharedApplication: function() {
//         return self.super.sharedApplication()
//     }
// })