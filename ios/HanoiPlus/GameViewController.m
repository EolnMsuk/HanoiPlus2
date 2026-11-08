#import "GameViewController.h"
#import "AssetLoader.h"
#import "BoardView.h"
#import "GameState.h"
#import "SoundPlayer.h"
#import <QuartzCore/QuartzCore.h>

@interface GameViewController ()
@property (nonatomic, strong) UIView *canvas;
@property (nonatomic, strong) UIView *screen;
@property (nonatomic, strong) BoardView *board;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UILabel *movesLabel;
@property (nonatomic, strong) GameState *state;
@property (nonatomic, strong) SoundPlayer *sounds;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, strong) NSDateFormatter *clockFormatter;
@property (nonatomic) BOOL inGame;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL transitioning;
@property (nonatomic) NSUInteger transitionGeneration;
@end

@implementation GameViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 480, 320)];
    self.canvas.clipsToBounds = YES;
    self.canvas.backgroundColor = UIColor.blackColor;
    [self.view addSubview:self.canvas];
    self.sounds = [[SoundPlayer alloc] init];
    self.clockFormatter = [[NSDateFormatter alloc] init];
    self.clockFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    self.clockFormatter.dateFormat = @"hh:mm";
    [self showHome];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeRight; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = self.view.safeAreaLayoutGuide.layoutFrame;
    CGFloat scale = MIN(safe.size.width / 480, safe.size.height / 320);
    if (scale <= 0) return;
    [self.board cancelDrag];
    self.canvas.bounds = CGRectMake(0, 0, 480, 320);
    self.canvas.transform = CGAffineTransformMakeScale(scale, scale);
    self.canvas.center = CGPointMake(CGRectGetMidX(safe), CGRectGetMidY(safe));
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [self.board cancelDrag];
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (UIImageView *)artworkView:(NSString *)name {
    UIImageView *view = [[UIImageView alloc] initWithImage:[AssetLoader imageNamed:name]];
    view.frame = self.canvas.bounds;
    view.contentMode = UIViewContentModeScaleToFill;
    return view;
}

- (void)replaceScreen:(UIView *)screen {
    [self.screen removeFromSuperview];
    self.screen = screen;
    screen.frame = self.canvas.bounds;
    [self.canvas addSubview:screen];
}

- (void)showHome {
    self.state = [GameState loadSavedGame];
    UIView *home = [[UIView alloc] initWithFrame:self.canvas.bounds];
    [home addSubview:[self artworkView:@"hanoi.jpg"]];
    UIButton *newGame = [UIButton buttonWithType:UIButtonTypeCustom];
    [newGame setImage:[AssetLoader imageNamed:@"new_game.png"] forState:UIControlStateNormal];
    newGame.frame = CGRectMake(0, 107, 227, 56);
    newGame.accessibilityLabel = @"New Game";
    [newGame addTarget:self action:@selector(startNewGame) forControlEvents:UIControlEventTouchUpInside];
    [home addSubview:newGame];
    UIButton *resume = [UIButton buttonWithType:UIButtonTypeCustom];
    [resume setImage:[AssetLoader imageNamed:@"continue.png"] forState:UIControlStateNormal];
    resume.frame = CGRectMake(0, 168, 227, 56);
    resume.accessibilityLabel = @"Continue";
    resume.enabled = self.state != nil;
    resume.alpha = resume.enabled ? 1 : 0.45;
    [resume addTarget:self action:@selector(continueGame) forControlEvents:UIControlEventTouchUpInside];
    [home addSubview:resume];
    [self replaceScreen:home];
}

- (void)startNewGame {
    if (self.transitioning) return;
    self.state = [GameState newGame];
    [self.state save];
    [self enterGame];
}

- (void)continueGame {
    if (self.transitioning) return;
    self.state = [GameState loadSavedGame];
    if (!self.state) { [self showHome]; return; }
    // A save during the completion animation advances exactly once on resume.
    if (self.state.game.phase == HPLevelComplete) { [self.state advance]; [self.state save]; }
    [self enterGame];
}

- (void)enterGame {
    self.inGame = YES;
    UIView *home = self.screen;
    [self renderGame];
    // Keep the home artwork behind the original 0.4-second fade.
    [self.canvas insertSubview:home belowSubview:self.screen];
    self.screen.alpha = 0;
    self.screen.userInteractionEnabled = NO;
    self.transitioning = YES;
    NSUInteger generation = ++self.transitionGeneration;
    [UIView animateWithDuration:0.4 animations:^{ self.screen.alpha = 1; } completion:^(BOOL finished) {
        [home removeFromSuperview];
        if (generation != self.transitionGeneration) return;
        self.transitioning = NO;
        self.screen.userInteractionEnabled = YES;
    }];
}

- (UILabel *)labelAt:(CGRect)frame color:(UIColor *)color size:(CGFloat)size {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.backgroundColor = UIColor.clearColor;
    label.textColor = color;
    label.font = [UIFont boldSystemFontOfSize:size];
    return label;
}

- (void)renderGame {
    [self stopClock];
    self.board = nil;
    self.clockLabel = nil;
    self.movesLabel = nil;
    if (self.state.game.phase == HPWon) {
        UIView *win = [[UIView alloc] initWithFrame:self.canvas.bounds];
        [win addSubview:[self artworkView:@"winScreen.jpg"]];
        UIColor *ink = [UIColor colorWithRed:60/255.0 green:48/255.0 blue:14/255.0 alpha:1];
        UILabel *total = [self labelAt:CGRectMake(250, 221, 220, 30) color:ink size:24];
        total.text = [NSString stringWithFormat:@"%lld", self.state.game.totalMoves];
        total.accessibilityLabel = [NSString stringWithFormat:@"Your moves: %@. Minimum moves: 2032.", total.text];
        [win addSubview:total];
        [self replaceScreen:win];
        return;
    }
    self.board = [[BoardView alloc] initWithState:self.state];
    __weak typeof(self) weakSelf = self;
    self.board.moveHandler = ^(HPMoveResult result) { [weakSelf handleMove:result]; };
    self.clockLabel = [self labelAt:CGRectMake(6, 298, 100, 24) color:[UIColor colorWithWhite:200/255.0 alpha:1] size:12];
    self.movesLabel = [self labelAt:CGRectMake(190, 298, 100, 24) color:[UIColor colorWithWhite:150/255.0 alpha:1] size:12];
    self.movesLabel.textAlignment = NSTextAlignmentCenter;
    [self.board addSubview:self.clockLabel];
    [self.board addSubview:self.movesLabel];
    [self replaceScreen:self.board];
    [self updateCounters];
    [self startClockIfNeeded];
}

- (void)updateCounters {
    HPGame game = self.state.game;
    self.movesLabel.text = [NSString stringWithFormat:@"%lld/%d", game.moves, HPGameMinimumMoves(&game)];
    self.movesLabel.accessibilityLabel = [NSString stringWithFormat:@"Moves: %lld. Minimum: %d.", game.moves, HPGameMinimumMoves(&game)];
    [self updateClock];
}

- (void)updateClock {
    self.clockFormatter.timeZone = NSTimeZone.localTimeZone;
    NSString *time = [self.clockFormatter stringFromDate:NSDate.date];
    self.clockLabel.text = [time hasPrefix:@"0"] ? [time substringFromIndex:1] : time;
}

- (void)startClockIfNeeded {
    if (!self.active || !self.inGame || !self.clockLabel || self.clockTimer) return;
    [self updateClock];
    __weak typeof(self) weakSelf = self;
    self.clockTimer = [NSTimer timerWithTimeInterval:10 repeats:YES block:^(NSTimer *timer) { [weakSelf updateClock]; }];
    [[NSRunLoop mainRunLoop] addTimer:self.clockTimer forMode:NSRunLoopCommonModes];
}

- (void)stopClock { [self.clockTimer invalidate]; self.clockTimer = nil; }

- (void)handleMove:(HPMoveResult)result {
    if (result == HPRejected) { [self.sounds vibrate]; return; }
    if (result == HPMoved || result == HPCompleted) { [self.state save]; [self updateCounters]; }
    if (result == HPCompleted) {
        [self.sounds playGong];
        [self beginLevelTransition];
    } else {
        // Original also clicks after a legal drop back onto its source post.
        [self.sounds playClick];
    }
}

- (void)beginLevelTransition {
    if (self.transitioning || self.state.game.phase != HPLevelComplete) return;
    self.transitioning = YES;
    self.screen.userInteractionEnabled = NO;
    [self stopClock];
    NSUInteger generation = ++self.transitionGeneration;
    [UIView animateWithDuration:1 animations:^{ self.screen.transform = CGAffineTransformMakeTranslation(-480, 0); }
                     completion:^(BOOL finished) {
        if (generation != self.transitionGeneration) return;
        [self.state advance];
        [self.state save];
        [self renderGame];
        self.screen.userInteractionEnabled = NO;
        self.screen.transform = CGAffineTransformMakeTranslation(480, 0);
        [UIView animateWithDuration:1 animations:^{ self.screen.transform = CGAffineTransformIdentity; }
                         completion:^(BOOL done) {
            if (generation != self.transitionGeneration) return;
            self.transitioning = NO;
            self.screen.userInteractionEnabled = YES;
        }];
    }];
}

- (void)sceneDidActivate {
    (void)self.view; // Ensure startup is complete before timer/lifecycle work.
    self.active = YES;
    [self startClockIfNeeded];
}

- (void)sceneWillDeactivate {
    self.active = NO;
    [self stopClock];
    [self.board cancelDrag];
    if (self.transitioning) {
        ++self.transitionGeneration;
        self.transitioning = NO;
        for (UIView *view in self.canvas.subviews.copy) { [view.layer removeAllAnimations]; [view removeFromSuperview]; }
        if (self.state.game.phase == HPLevelComplete) [self.state advance];
        if (self.inGame) [self renderGame];
    }
    if (self.inGame) [self.state save];
}

- (void)dealloc { [_clockTimer invalidate]; }
@end
