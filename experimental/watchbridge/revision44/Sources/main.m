#import <UIKit/UIKit.h>
@interface ReadinessSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation ReadinessSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
 if (![scene isKindOfClass:UIWindowScene.class]) return;
 self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
 UIViewController *controller = [UIViewController new];
 controller.view.backgroundColor = UIColor.systemBackgroundColor;
 UILabel *label = [UILabel new]; label.numberOfLines = 0;
 label.text = @"Readiness · Experimental\n\nOpen Readiness on your Apple Watch and allow access to Health.\n\nIf the watch keeps asking for age, height, and weight without a permission prompt, check that the signing tool granted the Watch app the HealthKit capability. Data already entered in Health does not grant an app access.\n\nThis iPhone companion packages the Watch app. It does not calculate a score or transfer your health profile.";
 label.textColor = UIColor.labelColor; label.translatesAutoresizingMaskIntoConstraints = NO;
 [controller.view addSubview:label];
 [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.leadingAnchor constant:24], [label.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-24], [label.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor]]];
 self.window.rootViewController = controller; [self.window makeKeyAndVisible];
}
@end
@interface ReadinessHostDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation ReadinessHostDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options { return YES; }
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
 UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Readiness" sessionRole:session.role];
 config.delegateClass = ReadinessSceneDelegate.class; return config;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ReadinessHostDelegate.class)); } }
