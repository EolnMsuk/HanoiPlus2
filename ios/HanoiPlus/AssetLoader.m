#import "AssetLoader.h"
#include <math.h>

@implementation AssetLoader
+ (UIImage *)imageNamed:(NSString *)name {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    UIImage *image = [cache objectForKey:name];
    if (image) return image;
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:nil];
    UIImage *source = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!source) {
        NSLog(@"Missing artwork: %@", name);
        return nil;
    }
    CGSize size = CGSizeMake(source.size.height, source.size.width);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = NO;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextTranslateCTM(context.CGContext, 0, size.height);
        CGContextRotateCTM(context.CGContext, -M_PI_2);
        [source drawInRect:(CGRect){CGPointZero, source.size}];
    }];
    [cache setObject:image forKey:name];
    return image;
}
@end
