#import "SoundPlayer.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@implementation SoundPlayer {
    AVAudioPlayer *_click;
    AVAudioPlayer *_gong;
    BOOL _foreground;
    BOOL _sessionActive;
    id _interruptionObserver;
    id _resetObserver;
}

static AVAudioPlayer *HPLoadSound(NSString *name) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:name withExtension:@"wav"];
    if (!url) return nil;
    NSError *error = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if (!player) NSLog(@"Optional sound %@ could not load: %@", name, error);
    // This is the asset's relative gain. iOS applies the user's media volume
    // to the final output; copying outputVolume here would apply it twice.
    player.volume = 1.0f;
    return player;
}

- (instancetype)init {
    if ((self = [super init])) {
        _click = HPLoadSound(@"click");
        _gong = HPLoadSound(@"gong");
        __weak SoundPlayer *weakSelf = self;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        _interruptionObserver = [center addObserverForName:AVAudioSessionInterruptionNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                [weakSelf handleInterruption:note];
            }];
        _resetObserver = [center addObserverForName:AVAudioSessionMediaServicesWereResetNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                [weakSelf resetAudioPlayers];
            }];
    }
    return self;
}

- (BOOL)activateSessionIfNeeded {
    if (!_foreground) return NO;
    if (_sessionActive) return YES;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    // Ambient honors the Ring/Silent switch and mixes with other apps' audio.
    if (![session setCategory:AVAudioSessionCategoryAmbient mode:AVAudioSessionModeDefault options:0 error:&error] ||
        ![session setActive:YES error:&error]) {
        NSLog(@"Optional game audio could not activate: %@", error);
        return NO;
    }
    _sessionActive = YES;
    [_click prepareToPlay];
    [_gong prepareToPlay];
    return YES;
}

- (void)activate {
    _foreground = YES;
    // Remain active between short effects so the hardware buttons adjust media
    // volume even when the player is currently waiting for the next move.
    [self activateSessionIfNeeded];
}

- (void)stopEffects {
    [_click stop];
    [_gong stop];
    _click.currentTime = 0;
    _gong.currentTime = 0;
}

- (void)deactivate {
    _foreground = NO;
    [self stopEffects];
    if (!_sessionActive) return;
    NSError *error = nil;
    if ([AVAudioSession.sharedInstance setActive:NO
            withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error]) {
        _sessionActive = NO;
    } else {
        NSLog(@"Game audio could not deactivate: %@", error);
    }
}

- (void)playEffect:(AVAudioPlayer *)player {
    if (!player || ![self activateSessionIfNeeded]) return;
    // Keep the prepared players warm; replace the previous short effect.
    [_click pause];
    [_gong pause];
    _click.currentTime = 0;
    _gong.currentTime = 0;
    if (![player play]) NSLog(@"Optional game sound could not play.");
}

- (void)playClick { [self playEffect:_click]; }
- (void)playGong { [self playEffect:_gong]; }
- (void)vibrate { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate); }

- (void)handleInterruption:(NSNotification *)notification {
    NSNumber *type = notification.userInfo[AVAudioSessionInterruptionTypeKey];
    if (!type) return;
    if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) {
        _sessionActive = NO; // The system has deactivated the session.
        [self stopEffects];
    } else if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded) {
        // Prepare for future moves; never replay an interrupted click or gong.
        [self activateSessionIfNeeded];
    }
}

- (void)resetAudioPlayers {
    [self stopEffects];
    _sessionActive = NO;
    _click = HPLoadSound(@"click");
    _gong = HPLoadSound(@"gong");
    [self activateSessionIfNeeded];
}

- (void)dealloc {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    if (_interruptionObserver) [center removeObserver:_interruptionObserver];
    if (_resetObserver) [center removeObserver:_resetObserver];
    [self deactivate];
}
@end
