#import <UIKit/UIKit.h>
#import "GameState.h"

NS_ASSUME_NONNULL_BEGIN
@interface BoardView : UIView
@property (nonatomic, strong, readonly) GameState *state;
@property (nonatomic, copy, nullable) void (^moveHandler)(HPMoveResult result);
@property (nonatomic, copy) NSArray<NSValue *> *reservedControlFrames;
@property (nonatomic) CGFloat bottomContentInset;
- (instancetype)initWithState:(GameState *)state;
- (void)cancelDrag;
- (void)freezeCompletedBoard;
@end
NS_ASSUME_NONNULL_END
