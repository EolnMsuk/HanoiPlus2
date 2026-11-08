#import "SceneDelegate.h"
#import "GameViewController.h"

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[GameViewController alloc] init];
    [self.window makeKeyAndVisible];
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    [(GameViewController *)self.window.rootViewController sceneDidActivate];
}
- (void)sceneWillResignActive:(UIScene *)scene {
    [(GameViewController *)self.window.rootViewController sceneWillDeactivate];
}
- (void)sceneDidEnterBackground:(UIScene *)scene {
    [(GameViewController *)self.window.rootViewController sceneWillDeactivate];
}
- (void)sceneDidDisconnect:(UIScene *)scene {
    [(GameViewController *)self.window.rootViewController sceneWillDeactivate];
}
@end
