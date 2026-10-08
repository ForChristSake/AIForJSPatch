//
//  RAIFloatingWindow.m
//  RuntimeAI
//

#import "RAIFloatingWindow.h"
#import "RuntimeAICore.h"

// 控制台面板控制器 (悬浮球展开后的可见视图)
@interface RAIConsoleViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) UITextView *resultView;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation RAIConsoleViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.96];
    self.view.layer.cornerRadius = 16;
    self.view.layer.masksToBounds = YES;

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat pad = 14;

    // 标题 + 关闭
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad, 12, w - 120, 28)];
    title.text = @"RuntimeAI 控制台";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:17];
    [self.view addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(w - 60, 8, 48, 34);
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor systemTealColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(_close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    // 结果区
    self.resultView = [[UITextView alloc]
        initWithFrame:CGRectMake(pad, 52, w - pad * 2, h - 52 - 62)];
    self.resultView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    self.resultView.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.resultView.editable = NO;
    self.resultView.selectable = YES;
    self.resultView.font = [UIFont systemFontOfSize:13];
    self.resultView.layer.cornerRadius = 8;
    [self.view addSubview:self.resultView];

    // 输入框
    self.inputField = [[UITextField alloc]
        initWithFrame:CGRectMake(pad, h - 52, w - pad * 2 - 70, 40)];
    self.inputField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:@"自然语言 / 指令, 如: 调用 AppDelegate 的方法"
                                        attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.6 alpha:1.0]}];
    self.inputField.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    self.inputField.textColor = [UIColor whiteColor];
    self.inputField.layer.cornerRadius = 8;
    self.inputField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 40)];
    self.inputField.leftViewMode = UITextFieldViewModeAlways;
    self.inputField.delegate = self;
    self.inputField.returnKeyType = UIReturnKeySend;
    [self.view addSubview:self.inputField];

    // 发送按钮
    UIButton *send = [UIButton buttonWithType:UIButtonTypeSystem];
    send.frame = CGRectMake(w - 56, h - 52, 46, 40);
    [send setTitle:@"发送" forState:UIControlStateNormal];
    [send setTitleColor:[UIColor systemTealColor] forState:UIControlStateNormal];
    [send addTarget:self action:@selector(_send) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:send];
}

- (void)_close {
    if (self.onClose) self.onClose();
}

- (void)_send {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return;
    self.inputField.text = @"";
    [self _append:[NSString stringWithFormat:@"\n>>> %@", text]];
    __weak typeof(self) wself = self;
    [[RuntimeAICore shared] handleNaturalLanguage:text completion:^(id result, NSError *error) {
        __strong typeof(wself) self = wself;
        if (self) [self _appendResult:result error:error];
    }];
}

- (void)_append:(NSString *)s {
    self.resultView.text = [self.resultView.text stringByAppendingString:s];
    [self.resultView scrollRangeToVisible:NSMakeRange(self.resultView.text.length, 0)];
}

- (void)_appendResult:(id)result error:(NSError *)error {
    NSString *line;
    if (error) {
        line = [NSString stringWithFormat:@"\n[错误] %@", error.localizedDescription];
    } else if ([result isKindOfClass:[NSDictionary class]]) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        line = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]
                 : [result description];
    } else if (result) {
        line = [NSString stringWithFormat:@"\n%@", result];
    } else {
        line = @"\n(无返回)";
    }
    [self _append:line];
}

// 回车即发送
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self _send];
    return YES;
}

@end

#pragma mark - 悬浮窗

@interface RAIFloatingWindow ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIButton *ballButton;
@property (nonatomic, strong) UIViewController *console;
@end

@implementation RAIFloatingWindow

+ (instancetype)sharedInstance {
    static RAIFloatingWindow *_instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (BOOL)isVisible {
    return _window != nil && !_window.hidden;
}

- (void)show {
    if ([self isVisible]) return;

    CGFloat side = 56.0;
    CGRect frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 76,
                              [UIScreen mainScreen].bounds.size.height - 180, side, side);

    UIWindow *win = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    win.windowLevel = UIWindowLevelAlert; // 浮于主界面之上
    win.backgroundColor = [UIColor clearColor];
    win.userInteractionEnabled = YES;

    // 用一个透明容器 VC 承载悬浮球按钮
    UIViewController *rootVC = [UIViewController new];
    rootVC.view.backgroundColor = [UIColor clearColor];

    UIButton *ball = [UIButton buttonWithType:UIButtonTypeCustom];
    ball.frame = frame;
    ball.backgroundColor = [UIColor colorWithRed:0.13 green:0.62 blue:0.47 alpha:0.95];
    ball.layer.cornerRadius = side / 2;
    ball.layer.shadowColor = [UIColor blackColor].CGColor;
    ball.layer.shadowOffset = CGSizeMake(0, 2);
    ball.layer.shadowOpacity = 0.3;
    ball.layer.shadowRadius = 4;
    [ball setTitle:@"AI" forState:UIControlStateNormal];
    [ball setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    ball.titleLabel.font = [UIFont boldSystemFontOfSize:18];

    // 拖拽 (pan) 与点击 (touchUpInside) 分离: 有位移时 touchUpInside 不会触发
    ball.userInteractionEnabled = YES;
    [ball addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePan:)]];
    [ball addTarget:self action:@selector(_tap) forControlEvents:UIControlEventTouchUpInside];

    [rootVC.view addSubview:ball];
    win.rootViewController = rootVC;
    [win makeKeyAndVisible];

    _window = win;
    _ballButton = ball;
}

- (void)hide {
    _window.hidden = YES;
    _window = nil;
    _ballButton = nil;
    _console = nil;
}

#pragma mark - 交互

- (void)_tap {
    if (_console.view.window) {
        [self _closeConsole];
    } else {
        [self _openConsole];
    }
}

- (void)_handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *ball = gesture.view;
    if (!ball) return;
    CGPoint translation = [gesture translationInView:ball.superview];
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint center = ball.center;
        center.x += translation.x;
        center.y += translation.y;
        // 限制在屏内
        UIView *superview = ball.superview;
        if (superview) {
            CGFloat half = ball.bounds.size.width / 2;
            center.x = MAX(half, MIN(superview.bounds.size.width - half, center.x));
            center.y = MAX(half, MIN(superview.bounds.size.height - half, center.y));
        }
        ball.center = center;
        [gesture setTranslation:CGPointZero inView:ball.superview];
    }
}

- (void)_openConsole {
    CGFloat w = MIN([UIScreen mainScreen].bounds.size.width - 32, 420);
    CGFloat h = MIN([UIScreen mainScreen].bounds.size.height * 0.55, 420);
    CGFloat x = ([UIScreen mainScreen].bounds.size.width - w) / 2;
    CGFloat y = [UIScreen mainScreen].bounds.size.height - h - 90;

    RAIConsoleViewController *vc = [[RAIConsoleViewController alloc] init];
    vc.view.frame = CGRectMake(x, y, w, h);
    vc.onClose = ^{ [self _closeConsole]; };

    [_window addSubview:vc.view];
    _console = vc;
}

- (void)_closeConsole {
    [self.console.view removeFromSuperview];
    self.console = nil;
}

@end