#import "BoardView.h"
#import "AssetLoader.h"
#include <math.h>

@implementation BoardView {
    NSArray<UIImage *> *_diskImages;
    UIImage *_base;
    UITouch *_activeTouch;
    NSInteger _dragPost;
    NSInteger _dragDisk;
    CGPoint _dragCenter;
    HPGame _completedBoard;
    BOOL _frozen;
}
@synthesize reservedControlFrames = _reservedControlFrames;

- (instancetype)initWithState:(GameState *)state {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 480, 320)])) {
        _state = state;
        _dragDisk = NSNotFound;
        self.multipleTouchEnabled = NO;
        self.exclusiveTouch = YES;
        self.opaque = YES;
        self.backgroundColor = UIColor.blackColor;
        _reservedControlFrames = @[];
        _base = [AssetLoader imageNamed:@"base.png"];
        NSMutableArray *images = [NSMutableArray arrayWithCapacity:HPMaxDisks];
        for (int disk = 0; disk < HPMaxDisks; ++disk) {
            UIImage *image = [AssetLoader imageNamed:[NSString stringWithFormat:@"disk_%d.png", disk]];
            [images addObject:image ?: [[UIImage alloc] init]];
        }
        _diskImages = images;
        self.accessibilityLabel = @"Hanoi board";
        self.accessibilityHint = @"Drag the top disk of a column to another column. Smaller disks go on larger disks.";
    }
    return self;
}

// Recovered original portrait y centers become logical landscape x centers.
static CGFloat HPPostCenter(NSInteger post) {
    const CGFloat centers[] = {74, 239, 407};
    return centers[post];
}

static NSInteger HPPostAtPoint(CGPoint point) {
    return point.x < 159 ? 0 : (point.x > 327 ? 2 : 1);
}

- (CGPoint)centerForDiskAtIndex:(NSInteger)index post:(NSInteger)post game:(HPGame)game {
    int originalX = 55;
    for (NSInteger i = 0; i < index; ++i) {
        UIImage *previous = _diskImages[game.disks[post][i]];
        originalX = (int)(originalX + previous.size.height * 0.5);
    }
    return CGPointMake(HPPostCenter(post), 320 - originalX);
}

- (void)drawDisk:(NSInteger)disk center:(CGPoint)center {
    UIImage *image = _diskImages[disk];
    [image drawInRect:CGRectMake(center.x - image.size.width * 0.5,
                                center.y - image.size.height * 0.5,
                                image.size.width, image.size.height)];
}

- (void)drawRect:(CGRect)rect {
    [UIColor.blackColor setFill];
    UIRectFill(self.bounds);
    [_base drawInRect:CGRectMake(0, 262, 480, 58)];
    HPGame game = _frozen ? _completedBoard : self.state.game;
    for (int post = 0; post < HPPostCount; ++post) {
        for (int i = 0; i < game.counts[post]; ++i) {
            int disk = game.disks[post][i];
            if (disk != _dragDisk) [self drawDisk:disk center:[self centerForDiskAtIndex:i post:post game:game]];
        }
    }
    if (_dragDisk != NSNotFound) [self drawDisk:_dragDisk center:_dragCenter];
}

- (void)setReservedControlFrames:(NSArray<NSValue *> *)frames {
    if ([_reservedControlFrames isEqualToArray:frames]) return;
    [self cancelDrag];
    _reservedControlFrames = [frames copy];
}

- (BOOL)isPlayablePoint:(CGPoint)point {
    if (!CGRectContainsPoint(self.bounds, point)) return NO;
    for (NSValue *value in self.reservedControlFrames) {
        if (CGRectContainsPoint(value.CGRectValue, point)) return NO;
    }
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_frozen || _activeTouch || self.state.game.phase != HPPlaying) return;
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self];
    if (![self isPlayablePoint:point]) return;
    HPGame game = self.state.game;
    NSInteger post = HPPostAtPoint(point);
    if (!game.counts[post]) return;
    _activeTouch = touch;
    _dragPost = post;
    _dragDisk = game.disks[post][game.counts[post] - 1];
    _dragCenter = [self centerForDiskAtIndex:game.counts[post] - 1 post:post game:game];
    [self setNeedsDisplay];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_activeTouch || ![touches containsObject:_activeTouch]) return;
    CGPoint point = [_activeTouch locationInView:self];
    HPGame game = self.state.game;
    NSInteger post = HPPostAtPoint(point);
    int count = game.counts[post] - (post == _dragPost ? 1 : 0);
    CGFloat highestY = 265;
    if (count) {
        int topDisk = game.disks[post][count - 1];
        CGPoint top = [self centerForDiskAtIndex:count - 1 post:post game:game];
        highestY = top.y - (_diskImages[topDisk].size.height + _diskImages[_dragDisk].size.height) * 0.5;
    }
    point.y = MIN(point.y, highestY);
    _dragCenter = point;
    [self setNeedsDisplay];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_activeTouch || ![touches containsObject:_activeTouch]) return;
    CGPoint point = [_activeTouch locationInView:self];
    if (![self isPlayablePoint:point]) { [self cancelDrag]; return; }
    HPMoveResult result = [self.state moveFrom:_dragPost to:HPPostAtPoint(point)];
    [self cancelDrag];
    if (self.moveHandler) self.moveHandler(result);
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_activeTouch && [touches containsObject:_activeTouch]) [self cancelDrag];
}

- (void)cancelDrag {
    // The model is unchanged until release, so cancellation never loses a disk.
    _activeTouch = nil;
    _dragDisk = NSNotFound;
    [self setNeedsDisplay];
}

- (void)freezeCompletedBoard {
    if (self.state.game.phase != HPLevelComplete) return;
    [self cancelDrag];
    _completedBoard = self.state.game;
    _frozen = YES;
    // The outgoing view must keep drawing the solved board after atomic advancement.
}
@end
