#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface AssetLoader : NSObject
// Gameplay files retain their source pixel orientation; rotate left exactly once.
+ (nullable UIImage *)imageNamed:(NSString *)name;
@end
NS_ASSUME_NONNULL_END
