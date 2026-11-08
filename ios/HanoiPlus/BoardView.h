#import <UIKit/UIKit.h>
#import "GameState.h"

NS_ASSUME_NONNULL_BEGIN
@interface BoardView : UIView
@property (nonatomic, strong, readonly) GameState *state;
@property (nonatomic, copy, nullable) void (^moveHandler)(HPMoveResult result);
- (instancetype)initWithState:(GameState *)state;
- (void)cancelDrag;
@end
NS_ASSUME_NONNULL_END
