#import <Foundation/Foundation.h>
#import "GameRules.h"

NS_ASSUME_NONNULL_BEGIN
@interface GameState : NSObject
@property (nonatomic, readonly) HPGame game;
+ (instancetype)newGame;
+ (nullable instancetype)loadSavedGame;
- (HPMoveResult)moveFrom:(NSInteger)from to:(NSInteger)to;
- (BOOL)advance;
- (BOOL)save;
@end
NS_ASSUME_NONNULL_END
