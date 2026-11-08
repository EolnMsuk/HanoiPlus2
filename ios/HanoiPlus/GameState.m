#import "GameState.h"
#import <CoreFoundation/CoreFoundation.h>
#include <limits.h>

@implementation GameState {
    HPGame _game;
}

+ (instancetype)newGame {
    GameState *state = [[self alloc] init];
    HPGameNew(&state->_game);
    return state;
}

- (HPGame)game { return _game; }

+ (NSURL *)saveURL {
    NSURL *directory = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                             inDomains:NSUserDomainMask] firstObject];
    return [[directory URLByAppendingPathComponent:@"HanoiPlus" isDirectory:YES]
            URLByAppendingPathComponent:@"save-v1.plist"];
}

static BOOL HPReadInteger(id value, long long maximum, long long *result) {
    if (![value isKindOfClass:[NSNumber class]] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
        CFNumberIsFloatType((__bridge CFNumberRef)value)) return NO;
    // Detect unsigned overflow before signed conversion.
    if ([value compare:@0] == NSOrderedAscending ||
        [value compare:@(maximum)] == NSOrderedDescending) return NO;
    *result = [value longLongValue];
    return YES;
}

+ (instancetype)loadSavedGame {
    NSURL *url = [self saveURL];
    NSNumber *size;
    if (!url || ![url getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedLongLongValue > 16384) return nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:nil];
    id payload = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil] : nil;
    if (![payload isKindOfClass:[NSDictionary class]]) return nil;
    long long version, level, moves, total, phase;
    if (!HPReadInteger(payload[@"version"], 1, &version) || version != 1 ||
        !HPReadInteger(payload[@"level"], HPLevelCount - 1, &level) ||
        !HPReadInteger(payload[@"moves"], LLONG_MAX, &moves) ||
        !HPReadInteger(payload[@"totalMoves"], LLONG_MAX, &total) ||
        !HPReadInteger(payload[@"phase"], HPWon, &phase)) return nil;
    NSArray *posts = payload[@"posts"];
    if (![posts isKindOfClass:[NSArray class]] || posts.count != HPPostCount) return nil;
    GameState *state = [[self alloc] init];
    HPGame game = {0};
    game.level = (int)level;
    game.moves = moves;
    game.totalMoves = total;
    game.phase = (HPPhase)phase;
    for (int post = 0; post < HPPostCount; ++post) {
        NSArray *stack = posts[post];
        if (![stack isKindOfClass:[NSArray class]] || stack.count > HPMaxDisks) return nil;
        game.counts[post] = (int)stack.count;
        for (NSUInteger i = 0; i < stack.count; ++i) {
            long long disk;
            if (!HPReadInteger(stack[i], HPMaxDisks - 1, &disk)) return nil;
            game.disks[post][i] = (int)disk;
        }
    }
    if (!HPGameIsValid(&game)) return nil;
    state->_game = game;
    return state;
}

- (HPMoveResult)moveFrom:(NSInteger)from to:(NSInteger)to {
    if (from < 0 || from >= HPPostCount || to < 0 || to >= HPPostCount) return HPRejected;
    return HPGameMove(&_game, (int)from, (int)to);
}

- (BOOL)advance { return HPGameAdvance(&_game); }

- (BOOL)save {
    if (!HPGameIsValid(&_game)) return NO;
    NSMutableArray *posts = [NSMutableArray arrayWithCapacity:HPPostCount];
    for (int post = 0; post < HPPostCount; ++post) {
        NSMutableArray *stack = [NSMutableArray arrayWithCapacity:_game.counts[post]];
        for (int i = 0; i < _game.counts[post]; ++i) [stack addObject:@(_game.disks[post][i])];
        [posts addObject:stack];
    }
    NSDictionary *payload = @{@"version": @1, @"level": @(_game.level), @"moves": @(_game.moves),
                              @"totalMoves": @(_game.totalMoves), @"phase": @(_game.phase), @"posts": posts};
    NSURL *url = [GameState saveURL];
    if (!url) return NO;
    NSError *error = nil;
    BOOL ready = [[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent]
                                         withIntermediateDirectories:YES attributes:nil error:&error];
    NSData *data = ready ? [NSPropertyListSerialization dataWithPropertyList:payload format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error] : nil;
    BOOL saved = data && [data writeToURL:url options:NSDataWritingAtomic error:&error];
    if (!saved) NSLog(@"Hanoi Plus save failed: %@", error);
    return saved;
}
@end
