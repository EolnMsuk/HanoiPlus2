#import "GameViewController.h"
#import "AssetLoader.h"
#import "BoardView.h"
#import "GameState.h"
#import "GameDuration.h"
#import "SoundPlayer.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static NSString *HPDurationString(long long seconds) {
    char buffer[HPDurationBufferSize];
    HPFormatDuration(seconds, buffer);
    return [NSString stringWithUTF8String:buffer];
}

@interface GameViewController ()
@property (nonatomic, strong) UIView *canvas;
@property (nonatomic, strong) UIView *screen;
@property (nonatomic, strong) BoardView *board;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UILabel *movesLabel;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIButton *restartButton;
@property (nonatomic, strong) UIButton *scoresButton;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *resetScoresButton;
@property (nonatomic, strong) UILabel *scoresTitleLabel;
@property (nonatomic, strong) UILabel *scoresStatusLabel;
@property (nonatomic, strong) UIScrollView *scoreList;
@property (nonatomic, strong) UIButton *resultButton;
@property (nonatomic, strong) UIButton *resultResetButton;
@property (nonatomic, strong) UIView *resultOverlay;
@property (nonatomic, strong) GameState *state;
@property (nonatomic, strong) SoundPlayer *sounds;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic) BOOL inGame;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL transitioning;
@property (nonatomic) BOOL completionSaved;
@property (nonatomic) BOOL completionSaveFailed;
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
    self.state = [GameState loadSavedGame];
    self.completionSaved = YES;
    [self showHome];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeRight; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    // Fill the landscape height. Keep the canvas proportional and horizontally
    // clear of the notch; apply vertical safe clearance to its contents instead.
    CGRect content = UIEdgeInsetsInsetRect(self.view.bounds,
        UIEdgeInsetsMake(0, insets.left, 0, insets.right));
    CGFloat scale = MIN(content.size.width / 480, content.size.height / 320);
    if (scale <= 0) return;
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    CGPoint center = CGPointMake(CGRectGetMidX(content), CGRectGetMidY(content));
    // Label refreshes can trigger layout; cancel only when geometry changes.
    if (!CGAffineTransformEqualToTransform(self.canvas.transform, transform) ||
        !CGPointEqualToPoint(self.canvas.center, center)) [self.board cancelDrag];
    self.canvas.bounds = CGRectMake(0, 0, 480, 320);
    self.canvas.transform = transform;
    self.canvas.center = center;
    [self layoutControls];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self.view setNeedsLayout];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    if (!CGSizeEqualToSize(size, self.view.bounds.size)) [self.board cancelDrag];
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)layoutControls {
    CGFloat scale = MAX(0.01, self.canvas.transform.a);
    CGFloat height = MAX(44, ceil(44 / scale));
    CGFloat width = MAX(96, ceil(44 / scale));
    CGFloat fontSize = MAX(16, 16 / scale);
    CGRect safe = [self.canvas convertRect:UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets)
                                  fromView:self.view];
    CGFloat top = MAX(0, CGRectGetMinY(safe));
    CGFloat bottom = MAX(0, 320 - CGRectGetMaxY(safe));
    CGFloat topY = top + 6;
    self.menuButton.frame = self.state.game.phase == HPWon && self.inGame ?
        CGRectMake(360, 270 - bottom, 112, height) : CGRectMake(6, topY, width, height);
    self.restartButton.frame = CGRectMake(474 - width, topY, width, height);
    self.scoresButton.frame = CGRectMake(22, 228, 181, height);
    self.backButton.frame = CGRectMake(6, topY, width, height);
    self.resetScoresButton.frame = CGRectMake(286, topY, 188, height);
    self.scoresTitleLabel.frame = CGRectMake(112, topY, 166, height);
    self.scoresStatusLabel.frame = CGRectMake(16, topY + height + 2, 448, 20);
    CGFloat listY = topY + height + 24;
    self.scoreList.frame = CGRectMake(16, listY, 448, MAX(0, 312 - bottom - listY));
    self.resultButton.frame = CGRectMake(self.resultResetButton ? 248 : 160, 226, 160, height);
    self.resultResetButton.frame = CGRectMake(72, 226, 160, height);
    self.clockLabel.frame = CGRectMake(6, 294 - bottom, 170, 24);
    self.movesLabel.frame = CGRectMake(185, 294 - bottom, 110, 24);
    UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
    self.menuButton.titleLabel.font = font;
    self.restartButton.titleLabel.font = font;
    self.scoresButton.titleLabel.font = font;
    self.backButton.titleLabel.font = font;
    self.resetScoresButton.titleLabel.font = font;
    self.resultButton.titleLabel.font = font;
    self.resultResetButton.titleLabel.font = font;
    if (self.board) {
        self.board.bottomContentInset = bottom;
        self.board.reservedControlFrames = @[[NSValue valueWithCGRect:self.menuButton.frame],
                                             [NSValue valueWithCGRect:self.restartButton.frame]];
    }
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
    [self layoutControls];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    button.layer.cornerRadius = 8;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithWhite:0.55 alpha:1].CGColor;
    button.exclusiveTouch = YES;
    button.accessibilityLabel = title;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UILabel *)labelAt:(CGRect)frame color:(UIColor *)color size:(CGFloat)size {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.backgroundColor = UIColor.clearColor;
    label.textColor = color;
    label.font = [UIFont boldSystemFontOfSize:size];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.6;
    return label;
}

- (void)clearGameplayViews {
    [self stopClock];
    [self.board cancelDrag];
    self.board.moveHandler = nil;
    self.board = nil;
    self.clockLabel = nil;
    self.movesLabel = nil;
    self.menuButton = nil;
    self.restartButton = nil;
    self.resultOverlay = nil;
    self.resultButton = nil;
    self.resultResetButton = nil;
}

- (void)showHome {
    [self.state pauseTiming];
    self.inGame = NO;
    [self clearGameplayViews];
    self.backButton = nil;
    self.resetScoresButton = nil;
    self.scoresTitleLabel = nil;
    self.scoresStatusLabel = nil;
    self.scoreList = nil;
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
    resume.enabled = self.state.hasRun;
    resume.alpha = resume.enabled ? 1 : 0.45;
    [resume addTarget:self action:@selector(continueGame) forControlEvents:UIControlEventTouchUpInside];
    [home addSubview:resume];
    self.scoresButton = [self buttonWithTitle:@"High Scores" action:@selector(showHighScores)];
    [home addSubview:self.scoresButton];
    [self replaceScreen:home];
}

- (void)startNewGame {
    if (self.transitioning) return;
    [self.state startNewGame];
    [self.state save];
    self.completionSaved = NO;
    self.completionSaveFailed = NO;
    [self enterGame];
}

- (void)continueGame {
    if (self.transitioning || !self.state.hasRun) return;
    self.completionSaveFailed = NO;
    // A new best must reopen on its solved board, awaiting explicit acknowledgement.
    // Only an ordinary (or migrated v1) completion may advance automatically.
    if (self.state.game.phase == HPLevelComplete && !self.state.pendingResult) {
        self.completionSaveFailed = ![self.state advanceAndSave];
    }
    [self enterGame];
}

- (void)enterGame {
    self.inGame = YES;
    self.transitioning = YES;
    UIView *home = self.screen;
    [self renderGame];
    UIView *incoming = self.screen;
    [self.canvas insertSubview:home belowSubview:incoming];
    incoming.alpha = 0;
    incoming.userInteractionEnabled = NO;
    NSUInteger generation = ++self.transitionGeneration;
    [UIView animateWithDuration:0.4 animations:^{ incoming.alpha = 1; } completion:^(BOOL finished) {
        [home removeFromSuperview];
        if (generation != self.transitionGeneration) return;
        self.transitioning = NO;
        incoming.userInteractionEnabled = self.active;
        [self resumeInteractivePlay];
    }];
}

- (void)menuPressed {
    if (self.transitioning || !self.inGame || self.state.game.phase == HPLevelComplete) return;
    [self.state pauseTiming];
    [self stopClock];
    [self.board cancelDrag];
    [self.state save];
    [self showHome];
}

- (void)restartPressed {
    if (self.transitioning || !self.inGame || self.state.game.phase != HPPlaying) return;
    [self.board cancelDrag];
    [self stopClock];
    if (![self.state restart]) return;
    [self.state save];
    [self renderGame];
    [self resumeInteractivePlay];
}

- (void)showHighScores {
    if (self.transitioning || self.inGame) return;
    self.scoresButton = nil;
    UIView *scores = [[UIView alloc] initWithFrame:self.canvas.bounds];
    scores.backgroundColor = UIColor.blackColor;
    self.scoresTitleLabel = [self labelAt:CGRectZero color:UIColor.whiteColor size:22];
    self.scoresTitleLabel.text = @"High Scores";
    self.scoresTitleLabel.textAlignment = NSTextAlignmentCenter;
    [scores addSubview:self.scoresTitleLabel];
    self.backButton = [self buttonWithTitle:@"Back" action:@selector(showHome)];
    [scores addSubview:self.backButton];
    self.resetScoresButton = [self buttonWithTitle:@"Reset Scores & Game" action:@selector(resetScoresAndGame)];
    self.resetScoresButton.accessibilityHint = @"Clear all recorded times and the saved game.";
    self.resetScoresButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    [scores addSubview:self.resetScoresButton];
    self.scoresStatusLabel = [self labelAt:CGRectZero color:UIColor.whiteColor size:12];
    [scores addSubview:self.scoresStatusLabel];
    UIScrollView *list = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scoreList = list;
    list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    list.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    list.alwaysBounceVertical = YES;
    for (int level = 0; level < HPLevelCount; ++level) {
        NSDictionary *record = [self.state recordForLevel:level];
        NSString *score = record ?
            [NSString stringWithFormat:@"%@ · %lld/%d moves",
                HPDurationString([record[@"seconds"] longLongValue]),
                [record[@"moves"] longLongValue], HPMinimumMovesForLevel(level)] : @"No completed time";
        UILabel *row = [self labelAt:CGRectMake(6, level * 72, 424, 68) color:UIColor.whiteColor size:18];
        row.numberOfLines = 2;
        row.text = [NSString stringWithFormat:@"Level %d · %d disks\n%@", level + 1, level + 3, score];
        row.isAccessibilityElement = YES;
        row.accessibilityLabel = row.text;
        [list addSubview:row];
    }
    list.contentSize = CGSizeMake(448, HPLevelCount * 72);
    [scores addSubview:list];
    [self replaceScreen:scores];
}

- (void)resetScoresAndGame {
    if (self.transitioning || self.inGame) return;
    if (![self.state resetScoresAndGame]) {
        self.scoresStatusLabel.text = @"Couldn’t reset scores and game. Tap again to retry.";
    } else {
        self.completionSaved = NO;
        self.completionSaveFailed = NO;
        [self showHighScores];
        self.scoresStatusLabel.text = @"Scores and saved game cleared.";
    }
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.scoresStatusLabel.text);
}

- (void)renderGame {
    [self clearGameplayViews];
    self.scoresButton = nil;
    self.backButton = nil;
    self.resetScoresButton = nil;
    self.scoresTitleLabel = nil;
    self.scoresStatusLabel = nil;
    self.scoreList = nil;
    if (self.state.game.phase == HPWon) {
        UIView *win = [[UIView alloc] initWithFrame:self.canvas.bounds];
        [win addSubview:[self artworkView:@"winScreen.jpg"]];
        UIColor *ink = [UIColor colorWithRed:60/255.0 green:48/255.0 blue:14/255.0 alpha:1];
        UILabel *total = [self labelAt:CGRectMake(250, 221, 220, 30) color:ink size:24];
        total.text = [NSString stringWithFormat:@"%lld", self.state.game.totalMoves];
        total.accessibilityLabel = [NSString stringWithFormat:@"Your moves: %@. Minimum moves: 2032.", total.text];
        [win addSubview:total];
        self.menuButton = [self buttonWithTitle:@"Menu" action:@selector(menuPressed)];
        [win addSubview:self.menuButton];
        [self replaceScreen:win];
        win.userInteractionEnabled = self.active && !self.transitioning;
        return;
    }
    self.board = [[BoardView alloc] initWithState:self.state];
    __weak GameViewController *weakSelf = self;
    self.board.moveHandler = ^(HPMoveResult result) { [weakSelf handleMove:result]; };
    self.clockLabel = [self labelAt:CGRectMake(6, 294, 170, 24) color:[UIColor colorWithWhite:200/255.0 alpha:1] size:12];
    self.movesLabel = [self labelAt:CGRectMake(185, 294, 110, 24) color:[UIColor colorWithWhite:150/255.0 alpha:1] size:12];
    self.movesLabel.textAlignment = NSTextAlignmentCenter;
    [self.board addSubview:self.clockLabel];
    [self.board addSubview:self.movesLabel];
    self.menuButton = [self buttonWithTitle:@"Menu" action:@selector(menuPressed)];
    self.restartButton = [self buttonWithTitle:@"Restart" action:@selector(restartPressed)];
    [self.board addSubview:self.menuButton];
    [self.board addSubview:self.restartButton];
    [self replaceScreen:self.board];
    self.screen.userInteractionEnabled = self.active && !self.transitioning;
    [self updateCounters];
    if (self.state.game.phase == HPLevelComplete) [self showCompletionResult];
}

- (void)updateCounters {
    HPGame game = self.state.game;
    self.movesLabel.text = [NSString stringWithFormat:@"%lld/%d", game.moves, HPGameMinimumMoves(&game)];
    self.movesLabel.accessibilityLabel = [NSString stringWithFormat:@"Moves: %lld. Minimum: %d.", game.moves, HPGameMinimumMoves(&game)];
    [self updateClock];
}

- (void)updateClock {
    self.clockLabel.text = self.state.timingEligible ?
        HPDurationString(self.state.elapsedMilliseconds / 1000) : @"--:--";
    self.clockLabel.accessibilityLabel = self.state.timingEligible ?
        [NSString stringWithFormat:@"Elapsed time: %@", self.clockLabel.text] :
        @"Elapsed time unavailable for this imported attempt. Restart to time this level.";
}

- (void)resumeInteractivePlay {
    if (!self.active || !self.inGame || self.transitioning || self.state.game.phase != HPPlaying) return;
    [self.state resumeTiming];
    [self updateClock];
    if (!self.state.timingEligible || !self.state.timingStarted || self.clockTimer) return;
    __weak GameViewController *weakSelf = self;
    self.clockTimer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf updateClock]; }];
    [[NSRunLoop mainRunLoop] addTimer:self.clockTimer forMode:NSRunLoopCommonModes];
}

- (void)stopClock { [self.clockTimer invalidate]; self.clockTimer = nil; }

- (void)handleMove:(HPMoveResult)result {
    if (!self.active || !self.inGame || self.transitioning) return;
    if (result == HPRejected) { [self.sounds vibrate]; return; }
    if (result == HPMoved || result == HPCompleted) {
        BOOL saved = [self.state save]; // Board, elapsed checkpoint, record and pending result together.
        [self updateCounters];
        if (result == HPCompleted) {
            self.completionSaved = saved;
            self.completionSaveFailed = !saved;
            [self stopClock];
            [self.sounds playGong];
            if (self.state.pendingResult || !saved) [self showCompletionResult];
            else [self beginLevelTransition];
            return;
        }
    }
    [self resumeInteractivePlay];
    // Original also clicks after a legal drop back onto its source post.
    [self.sounds playClick];
}

- (void)showCompletionResult {
    [self stopClock];
    [self.resultOverlay removeFromSuperview];
    UIView *overlay = [[UIView alloc] initWithFrame:self.canvas.bounds];
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
    self.resultOverlay = overlay;
    BOOL newBest = self.state.pendingResult != nil;
    self.resultResetButton = nil;
    UILabel *title = [self labelAt:CGRectMake(60, 82, 360, 38) color:UIColor.whiteColor size:28];
    title.textAlignment = NSTextAlignmentCenter;
    title.text = newBest ? @"New Best Time" : @"Level Complete";
    [overlay addSubview:title];
    UILabel *time = [self labelAt:CGRectMake(60, 126, 360, 30) color:UIColor.whiteColor size:24];
    time.textAlignment = NSTextAlignmentCenter;
    time.text = self.state.timingEligible ? HPDurationString(self.state.elapsedMilliseconds / 1000) : @"Time unavailable";
    [overlay addSubview:time];
    UILabel *moves = [self labelAt:CGRectMake(60, 158, 360, 26) color:UIColor.whiteColor size:18];
    moves.textAlignment = NSTextAlignmentCenter;
    HPGame game = self.state.game;
    moves.text = [NSString stringWithFormat:@"%lld/%d moves", game.moves, HPGameMinimumMoves(&game)];
    [overlay addSubview:moves];
    UILabel *status = [self labelAt:CGRectMake(65, 186, 350, 34) color:UIColor.whiteColor size:13];
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 2;
    status.text = self.completionSaveFailed ? @"Couldn’t save progress. Tap below to retry." : @"";
    [overlay addSubview:status];
    NSString *action = newBest ? (game.level == HPLevelCount - 1 ? @"Finish" : @"Next Level") : @"Retry Save";
    self.resultButton = [self buttonWithTitle:action action:@selector(acknowledgeResult)];
    [overlay addSubview:self.resultButton];
    if (newBest) {
        self.resultResetButton = [self buttonWithTitle:@"Reset" action:@selector(resetCompletedLevel)];
        self.resultResetButton.accessibilityHint = @"Keep this record and replay the same level.";
        [overlay addSubview:self.resultResetButton];
    }
    [self.board addSubview:overlay];
    [self layoutControls];
    self.board.accessibilityElements = newBest ?
        @[title, time, moves, status, self.resultResetButton, self.resultButton] :
        @[title, time, moves, status, self.resultButton];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, title);
}

- (BOOL)saveCompletionIfNeeded {
    if (!self.completionSaved) {
        self.completionSaved = [self.state save];
        if (!self.completionSaved) {
            self.completionSaveFailed = YES;
            [self showCompletionResult];
            return NO;
        }
    }
    return YES;
}

- (void)acknowledgeResult {
    if (self.transitioning || !self.inGame || self.state.game.phase != HPLevelComplete) return;
    if (![self saveCompletionIfNeeded]) return;
    [self beginLevelTransition];
}

- (void)resetCompletedLevel {
    if (self.transitioning || !self.inGame || self.state.game.phase != HPLevelComplete || !self.state.pendingResult) return;
    if (![self saveCompletionIfNeeded]) return;
    if (![self.state resetCompletedLevelAndSave]) {
        self.completionSaveFailed = YES;
        [self showCompletionResult];
        return;
    }
    ++self.transitionGeneration;
    self.completionSaved = NO;
    self.completionSaveFailed = NO;
    [self renderGame];
    [self resumeInteractivePlay];
}

- (void)beginLevelTransition {
    if (self.transitioning || self.state.game.phase != HPLevelComplete) return;
    UIView *outgoing = self.screen;
    [self.board freezeCompletedBoard];
    // Commit acknowledgement/advancement before starting either half of the slide.
    // On failure the model rolls back and the solved board stays available for retry.
    if (![self.state advanceAndSave]) {
        self.completionSaveFailed = YES;
        [self showCompletionResult];
        return;
    }
    self.transitioning = YES;
    self.completionSaveFailed = NO;
    [self stopClock];
    NSUInteger generation = ++self.transitionGeneration;
    [self renderGame];
    UIView *incoming = self.screen;
    incoming.userInteractionEnabled = NO;
    outgoing.frame = self.canvas.bounds;
    outgoing.userInteractionEnabled = NO;
    [self.canvas addSubview:outgoing];
    incoming.transform = CGAffineTransformMakeTranslation(480, 0);
    [UIView animateWithDuration:1 animations:^{ outgoing.transform = CGAffineTransformMakeTranslation(-480, 0); }
                     completion:^(BOOL finished) {
        if (generation != self.transitionGeneration) return;
        [outgoing removeFromSuperview];
        [UIView animateWithDuration:1 animations:^{ incoming.transform = CGAffineTransformIdentity; }
                         completion:^(BOOL done) {
            if (generation != self.transitionGeneration) return;
            self.transitioning = NO;
            incoming.userInteractionEnabled = self.active;
            [self resumeInteractivePlay];
        }];
    }];
}

- (void)sceneDidActivate {
    (void)self.view;
    self.active = YES;
    self.screen.userInteractionEnabled = !self.transitioning;
    if (self.resultOverlay && !self.transitioning) [self showCompletionResult];
    [self resumeInteractivePlay];
}

- (void)sceneWillDeactivate {
    self.active = NO;
    [self.state pauseTiming];
    [self stopClock];
    [self.board cancelDrag];
    if (self.transitioning) {
        ++self.transitionGeneration;
        self.transitioning = NO;
        for (UIView *view in self.canvas.subviews.copy) {
            [view.layer removeAllAnimations];
            [view removeFromSuperview];
        }
        // The next state was already committed; cleanup must never advance it again.
        if (self.inGame) [self renderGame];
    }
    self.screen.userInteractionEnabled = NO;
    if (self.inGame) {
        BOOL saved = [self.state save];
        if (self.state.game.phase == HPLevelComplete && saved) {
            self.completionSaved = YES;
            self.completionSaveFailed = NO;
        }
    }
}

- (void)dealloc { [_clockTimer invalidate]; }
@end
