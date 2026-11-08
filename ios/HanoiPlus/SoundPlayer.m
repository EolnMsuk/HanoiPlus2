#import "SoundPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

@implementation SoundPlayer {
    SystemSoundID _click;
    SystemSoundID _gong;
}

static SystemSoundID HPLoadSound(NSString *name) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:name withExtension:@"wav"];
    if (!url) return 0;
    SystemSoundID sound = 0;
    OSStatus result = AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &sound);
    if (result != kAudioServicesNoError) {
        NSLog(@"Optional sound %@ could not load (%d)", name, (int)result);
        return 0;
    }
    return sound;
}

- (instancetype)init {
    if ((self = [super init])) {
        _click = HPLoadSound(@"click");
        _gong = HPLoadSound(@"gong");
    }
    return self;
}
- (void)playClick { if (_click) AudioServicesPlaySystemSound(_click); }
- (void)playGong { if (_gong) AudioServicesPlaySystemSound(_gong); }
- (void)vibrate { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate); }
- (void)dealloc {
    if (_click) AudioServicesDisposeSystemSoundID(_click);
    if (_gong) AudioServicesDisposeSystemSoundID(_gong);
}
@end
