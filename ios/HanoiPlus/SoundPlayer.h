#import <Foundation/Foundation.h>

@interface SoundPlayer : NSObject
// Foreground audio uses the system media volume and respects silent mode.
- (void)activate;
- (void)deactivate;
- (void)playClick;
- (void)playGong;
- (void)vibrate;
@end
