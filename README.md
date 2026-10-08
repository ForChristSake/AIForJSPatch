# RuntimeAI — 运行时 AI 代理 SDK

面向 iOS 开发与内测调试的嵌入式 SDK, 在进程内打通 **调用大模型 / 运行时修改方法 / 运行时调用方法** 三项能力, 以悬浮窗作为交互入口。

> 定位约束: 仅用于 Debug / 内测调试, 请勿随正式包上架 (规避 Apple Guideline 2.5.2 的运行时下载执行约束)。

---

## 目录结构

```
RuntimeAI/
├── RuntimeAI.h                 统一导入头
├── Headers/
│   └── RuntimeAI.h
├── Core/
│   ├── RuntimeAICore.h/.m      调度核心: 动作注册 + 意图判别(改/调/查) + 路由 + 结果聚合
├── Runtime/
│   ├── MethodSwizzler.h/.m     方法修改器 (OC 回退路径): 可逆的带方法交换
│   ├── MethodInvoker.h/.m      方法调用器: 类名+选择器反射调用, 返回 JSON 化结果
│   └── RAIMessageBridge.h/.m   NSProxy 消息转发桥: 对象级代理 + 调用日志
├── Scripting/
│   ├── JSPatchScriptEngine.h/.m    JSPatch 脚本引擎适配层 (defineClass 改方法, 方法修改主路径)
│   ├── AIScriptGenerator.h/.m      AI 驱动的 JSPatch 脚本生成器 (自然语言 → 脚本 → 执行)
│   └── RuntimeClassIndexer.h/.m    运行时类/方法索引器 (无目标类时自动检索候选)
├── Samples/
│   └── demo_patch.js          JSPatch 方法修改示例脚本
├── LLM/
│   ├── RAILLMProvider.h        大模型厂商无关抽象协议
│   └── RAIOpenAICompatibleProvider.h/.m   OpenAI Chat Completions 兼容参考实现
├── UI/
│   └── RAIFloatingWindow.h/.m  悬浮窗 + 控制台面板
└── (外部依赖) Vendor/JSPatch/    JSPatch 官方内核 (JPEngine.h/.m + JSPatch.js), MIT 开源
```

---

## 在 Mac 上新建 Xcode 工程并集成

你需要 **Objective-C** `#import` 的能力, 纯 OC 工程或混编工程均可。

1. 在 Xcode 新建工程, 语言选择 **Objective-C** (或勾选混编)。
2. 把 `RuntimeAI/` 源码文件夹 **整体拖入** 工程 (勾选 "Copy items if needed" 与 target 成员)。
3. 把 `Vendor/JSPatch/JSPatch/` 下的 **三个文件** `JPEngine.h`、`JPEngine.m`、`JSPatch.js` 拖入工程 (JSPatch 引擎本体)。
4. 在 `TARGETS → Build Phases → Link Binary With Libraries` 添加 `JavaScriptCore.framework`。
5. 在 `TARGETS → Build Settings` 确认 Foundation/UIKit 依赖正常 (默认已链接)。
6. 若建的是 Swift 工程, 首次会有 "Bridging Header" 提示一一创建桥接头即可在 Swift 中调用。

### 最小接入示例 (AppDelegate.m)

```objc
#import <RuntimeAI/RuntimeAI.h>

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    RuntimeAICore *core = [RuntimeAICore shared];

    // 1. 注入大模型 Provider (OpenAI 兼容协议示例; API Key 请走后端中转, 勿随包分发)
    core.llmProvider = [[RAIOpenAICompatibleProvider alloc]
        initWithEndpoint:@"https://你的端点/v1/chat/completions"
                   apiKey:@"sk-xxx"
                    model:@"gpt-4o-mini"];

    // 2. 注册一个自定义动作 (可选)
    [core registerAction:@"ping" handler:^(NSDictionary *params, id *result, NSError **error) {
        *result = @"pong";
    }];

    // 3. 显示悬浮窗
    [[RAIFloatingWindow sharedInstance] show];

    return YES;
}
```

---

## 使用方式

### 悬浮窗

- 屏幕角落的半透明圆形按钮 "AI" 就是悬浮窗, 可拖拽到任意位置。
- 点击展开控制台面板, 底部输入框接收 **自然语言** 指令, 回车/发送执行, 顶部回显结果。

### 意图判别规则 (改 / 调 / 查)

`RuntimeAICore.classifyAndRoute:` 按优先级三层判定:

1. **显式声明** — 指令带 `type` 字段 (`"modify"` / `"invoke"` / `"query"` 或中文别名) 时直接采信。
2. **词法特征** — 无显式类型时按动词归类:
   - 修改动词: `替换 覆盖 注入 打日志 hook swizzle modify replace override inject log`
   - 调用动词: `调用 执行 运行 invoke call execute run get`
3. **兜底** — 无法识别时降级为 **只读查询**, 绝不猜成修改 (避免误 swizzle 污染宿主)。

### 直接调用方法 (代码方式)

```objc
[[RuntimeAICore shared] invokeClass:@"MyViewController"
                           selector:@"reloadData"
                               args:@[]
                         completion:^(id result, NSError *error) {
    // result 为返回值
}];
```

### 方法修改 — JSPatch 脚本主路径 (推荐)

JSPatch 是方法修改的主路径, 用 `defineClass` 在运行时重写任意类的方法实现。语法直观, 改动集中在 JS 脚本里, 不污染 OC 代码。

```objc
// 1. 直接执行一段 JS 脚本 (defineClass 改写)
NSError *err = nil;
BOOL ok = [[RuntimeAICore shared] evaluateJSPatchScript:
    @"require('UIViewController'); "
     "defineClass('UIViewController', {"
     "  viewDidLoad: function() {"
     "    self.super.viewDidLoad();"
     "    console.log('[JSPatch] viewDidLoad 被调用');"
     "  }"
     "});"
    error:&err];

// 2. 也可以从 .js 文件加载 (适合脚本从服务端下发)
NSString *path = [[NSBundle mainBundle] pathForResource:@"demo_patch" ofType:@"js"];
[[JSPatchScriptEngine sharedInstance] evaluateScriptFromPath:path error:&err];
```

JSPatch 脚本的基本结构:

```javascript
require('UIView, UIColor')       // 导入要用到的 OC 类
defineClass('MyViewController', { // 实例方法写在这里
    viewDidLoad: function() {
        self.super.viewDidLoad()   // 保留原逻辑
        self.setTitle_('已被 JSPatch 改写')
    },
    // 多参数方法: 把 OC 的冒号转下划线, 末尾留一个 _
    setTitle_forIndex_: function(title, idx) {
        self.super.setTitle_forIndex_(title, idx)
    }
}, {                                // 类方法写在第二个字典 (可选)
    sharedInstance: function() {
        return self.super.sharedInstance()
    }
})
```

要点:
- 调用原方法用 `self.super.原方法名()` 或 `self.ORIG方法名()`。
- OC 方法名中的冒号换成下划线 (`setTitle:` → `setTitle_`)。
- 所有 OC 对象在 JS 中都是对象, 直接 `.方法()` 调用。

### 方法修改 — AI 生成 JSPatch 脚本 (自然语言直接改方法)

可以让大模型直接根据一句自然语言生成并执行 JSPatch 脚本。生成前 SDK 会自动
用 runtime 采集目标类的方法列表作为上下文注入, 让模型更准确地选择 hook 点。

```objc
[[RuntimeAICore shared] applyAIIntent:@"把 MyService 的 compute 方法返回值加个 [AI] 前缀"
                          targetClass:@"MyService"
                           completion:^(id script, NSError *error) {
    if (script) NSLog(@"已应用的脚本:\n%@", script);
    else        NSLog(@"失败: %@", error);
}];
```

背后做的事:
1. 扫描 `MyService` 的方法列表 → 拼进上下文。
2. 向大模型注入 JSPatch 语法规范 + 「只输出纯脚本」约束。
3. 模型返回 `defineClass` 脚本 → 清洗 markdown 包裹 → 交给 JSPatch 引擎执行。

> 如果大模型未配置 Provider, 会读取 `RuntimeAICore.shared.llmProvider`。

### 自动候选检索: 不给类名也能找到该 hook 谁

当你只描述需求、不指定 `targetClass` 时, SDK 会自动用 `RuntimeClassIndexer`
在运行时遍历全 App 已注册的类与方法, 从意图中提取关键词做匹配, 把最相关的
几个候选类+命中方法注入上下文。大模型基于真实存在的类名和方法名来决定 hook 谁,
而不是凭空猜测。

```objc
// 不给 targetClass, 让 SDK 自己找
[[RuntimeAICore shared] applyAIIntent:@"把登录失败弹窗的错误文案改掉"
                          targetClass:nil
                           completion:^(id script, NSError *error) { ... }];
```

候选检索的规则:
- 从意图里提取英文 token, 对类名和方法名做子串匹配打分。
- 过滤掉 UIKit / Foundation 等系统框架前缀 (NS/UI/CG/CA 等), 只返回 App 业务类。
- 按命中度取 top 6 个候选, 保持上下文精简, 不浪费 token。
- 若完全无命中, 降级为「模型自行判断」, system prompt 已约束其禁止编造不存在的类名。

也可以单独使用索引器:

```objc
NSArray *hits = [[RuntimeClassIndexer sharedInstance] findCandidatesForIntent:@"登录失败弹窗"];
for (RAIIndexHit *hit in hits) {
    NSLog(@"候选类: %@ (得分 %ld), 命中方法: %@",
        hit.className, (long)hit.score, hit.matchedMethods);
}
```

### 修改方法 (OC 回退路径)

```objc
Class cls = NSClassFromString(@"MyService");
SEL sel = NSSelectorFromString(@"compute:");
IMP imp = [MethodSwizzler impForBlock:^(id target, SEL originalSel, ...) {
    NSLog(@"[hook] 进入 compute:");
    return nil; // 按原方法返回值类型调整
}];
NSError *err = nil;
[MethodSwizzler swizzleInstanceMethod:sel onClass:cls withReplacement:imp storingOriginal:NULL error:&err];
// 调试结束统一还原
[MethodSwizzler revertAll];
```

---

## 设计要点与边界

- 三块能力统一为 **"动作 + 参数 + handler"** 抽象, 自然语言 / 脚本 / 手动点击最终都走 `executeAction:`。
- 意图判别内聚在 `RuntimeAICore` 内部, 不拆分独立路由类。
- 方法修改主路径是 **JSPatch 脚本** (defineClass 改方法), AI 生成脚本是其上层能力。
- AI 生成脚本靠 **runtime 类/方法索引** 提供候选上下文, 不依赖向量/RAG, 零额外 token 成本。
- swizzle 每次替换记录原始 IMP, 提供 `revertAll` 供调试会话结束后还原。
- `MethodInvoker` 对参数超 2 个或复杂场景用 `NSInvocation` 兜底; 结构体等复杂返回需利用带签名的重载。
- **风险**: swizzle 不可滥用、跨线程反射调用需归队到主线程 / 串行队列、大模型 Provider 需正确处理 token。

## 后续可扩展

- `RAIOpenAICompatibleProvider` 的流式能力: 当前用完整响应模拟逐字回调, 真实 SSE 解析可替换进 `streamChatWithMessages:`。
- `MethodInvoker` 增加显式参数类型签名支持, 完善结构体返回。
- 将大模型输出进一步结构化为标准化动作调用 (Agent 闭环)。
- `RuntimeClassIndexer` 支持自定义前缀白名单/黑名单, 按业务模块过滤。