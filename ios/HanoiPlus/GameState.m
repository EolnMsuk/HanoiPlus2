#import "GameState.h"
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#include <limits.h>
#include <math.h>

static BOOL HPReadInteger(id value, long long maximum, long long *result) {
    if (![value isKindOfClass:[NSNumber class]] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
        CFNumberIsFloatType((__bridge CFNumberRef)value)) return NO;
    if ([value compare:@0] == NSOrderedAscending ||
        [value compare:@(maximum)] == NSOrderedDescending) return NO;
    *result = [value longLongValue];
    return YES;
}

static BOOL HPReadBoolean(id value, BOOL *result) {
    if (![value isKindOfClass:[NSNumber class]] ||
        CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) return NO;
    *result = [value boolValue];
    return YES;
}

static NSDictionary *HPReadPayload(NSURL *url) {
    NSNumber *size = nil;
    if (!url || ![url getResourceValue:&size forKey:NSURLFileSizeKey error:nil] ||
        size.unsignedLongLongValue > 16384) return nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:nil];
    id payload = data && data.length <= 16384 ?
        [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil] : nil;
    return [payload isKindOfClass:[NSDictionary class]] ? payload : nil;
}

static BOOL HPReadGame(id run, HPGame *result) {
    if (![run isKindOfClass:[NSDictionary class]]) return NO;
    long long level, moves, total, phase;
    if (!HPReadInteger(run[@"level"], HPLevelCount - 1, &level) ||
        !HPReadInteger(run[@"moves"], LLONG_MAX, &moves) ||
        !HPReadInteger(run[@"totalMoves"], LLONG_MAX, &total) ||
        !HPReadInteger(run[@"phase"], HPWon, &phase)) return NO;
    NSArray *posts = run[@"posts"];
    if (![posts isKindOfClass:[NSArray class]] || posts.count != HPPostCount) return NO;
    HPGame game = {0};
    game.level = (int)level;
    game.moves = moves;
    game.totalMoves = total;
    game.phase = (HPPhase)phase;
    for (int post = 0; post < HPPostCount; ++post) {
        NSArray *stack = posts[post];
        if (![stack isKindOfClass:[NSArray class]] || stack.count > HPMaxDisks) return NO;
        game.counts[post] = (int)stack.count;
        for (NSUInteger i = 0; i < stack.count; ++i) {
            long long disk;
            if (!HPReadInteger(stack[i], HPMaxDisks - 1, &disk)) return NO;
            game.disks[post][i] = (int)disk;
        }
    }
    if (!HPGameIsValid(&game)) return NO;
    *result = game;
    return YES;
}

static NSDictionary *HPReadRecord(id entry, int level) {
    if (![entry isKindOfClass:[NSDictionary class]]) return nil;
    long long seconds, moves;
    if (!HPReadInteger(entry[@"seconds"], LLONG_MAX / 1000, &seconds) ||
        !HPReadInteger(entry[@"moves"], LLONG_MAX, &moves) ||
        moves < HPMinimumMovesForLevel(level)) return nil;
    return @{@"seconds": @(seconds), @"moves": @(moves)};
}

@implementation GameState {
    HPGame _game;
    BOOL _hasRun;
    BOOL _timingStarted;
    BOOL _timingEligible;
    long long _accumulatedMilliseconds;
    CFTimeInterval _activeStart; // Memory only; never serialized.
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *_bestRecords;
    NSDictionary<NSString *, NSNumber *> *_pendingResult;
}

- (instancetype)init {
    if ((self = [super init])) _bestRecords = [NSMutableDictionary dictionary];
    return self;
}

- (HPGame)game { return _game; }
- (BOOL)hasRun { return _hasRun; }
- (BOOL)timingStarted { return _timingStarted; }
- (BOOL)timingEligible { return _timingEligible; }
- (NSDictionary<NSString *, NSNumber *> *)pendingResult { return _pendingResult; }

+ (NSURL *)saveURLForVersion:(int)version {
    NSURL *directory = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                             inDomains:NSUserDomainMask] firstObject];
    return [[directory URLByAppendingPathComponent:@"HanoiPlus" isDirectory:YES]
            URLByAppendingPathComponent:[NSString stringWithFormat:@"save-v%d.plist", version]];
}

- (void)resetTiming {
    _accumulatedMilliseconds = 0;
    _activeStart = 0;
    _timingStarted = NO;
    _timingEligible = YES;
    _pendingResult = nil;
}

- (void)startNewGame {
    HPGameNew(&_game);
    _hasRun = YES;
    [self resetTiming]; // Records belong to the store, not the current run.
}

- (NSDictionary<NSString *, NSNumber *> *)recordForLevel:(NSInteger)level {
    if (level < 0 || level >= HPLevelCount) return nil;
    return _bestRecords[[NSString stringWithFormat:@"%ld", (long)level]];
}

- (long long)elapsedAt:(CFTimeInterval)now {
    if (!_activeStart) return _accumulatedMilliseconds;
    long double interval = floorl(fmax(0, now - _activeStart) * 1000.0L);
    if (interval >= (long double)(LLONG_MAX - _accumulatedMilliseconds)) return LLONG_MAX;
    return _accumulatedMilliseconds + (long long)interval;
}

- (long long)elapsedMilliseconds { return [self elapsedAt:CACurrentMediaTime()]; }

- (void)resumeTiming {
    if (_hasRun && _game.phase == HPPlaying && _timingEligible && _timingStarted && !_activeStart) {
        _activeStart = CACurrentMediaTime();
    }
}

- (void)pauseTiming {
    _accumulatedMilliseconds = self.elapsedMilliseconds;
    _activeStart = 0; // Repeated lifecycle callbacks cannot count the interval twice.
}

- (HPMoveResult)moveFrom:(NSInteger)from to:(NSInteger)to {
    if (!_hasRun || from < 0 || from >= HPPostCount || to < 0 || to >= HPPostCount) return HPRejected;
    CFTimeInterval releaseTime = CACurrentMediaTime();
    HPMoveResult result = HPGameMove(&_game, (int)from, (int)to);
    if (result == HPMoved && !_timingStarted) {
        _timingStarted = YES;
        if (_timingEligible) _activeStart = releaseTime;
    } else if (result == HPCompleted) {
        _accumulatedMilliseconds = [self elapsedAt:releaseTime];
        _activeStart = 0; // Freeze at the winning release, before any UI/audio.
        if (_timingEligible) {
            long long seconds = _accumulatedMilliseconds / 1000;
            NSDictionary *best = [self recordForLevel:_game.level];
            if (!best || seconds < [best[@"seconds"] longLongValue]) {
                NSDictionary *record = @{@"seconds": @(seconds), @"moves": @(_game.moves)};
                _bestRecords[[NSString stringWithFormat:@"%d", _game.level]] = record;
                _pendingResult = @{@"level": @(_game.level), @"seconds": @(seconds),
                                   @"moves": @(_game.moves), @"minimum": @(HPGameMinimumMoves(&_game))};
            }
        }
    }
    return result;
}

- (BOOL)restart {
    if (!_hasRun || !HPGameRestart(&_game)) return NO;
    [self resetTiming];
    return YES;
}

- (BOOL)finishLevelAndSave:(BOOL)replay {
    if (!_hasRun || _game.phase != HPLevelComplete) return NO;
    HPGame previous = _game;
    long long elapsed = _accumulatedMilliseconds;
    BOOL started = _timingStarted, eligible = _timingEligible;
    NSDictionary *pending = _pendingResult;
    if (!(replay ? HPGameResetCompletedLevel(&_game) : HPGameAdvance(&_game))) return NO;
    if (_game.phase == HPPlaying) [self resetTiming];
    else _pendingResult = nil;
    if ([self save]) return YES;
    _game = previous;
    _accumulatedMilliseconds = elapsed;
    _timingStarted = started;
    _timingEligible = eligible;
    _pendingResult = pending;
    return NO;
}

- (BOOL)advanceAndSave { return [self finishLevelAndSave:NO]; }
- (BOOL)restartCompletedLevelAndSave { return [self finishLevelAndSave:YES]; }

- (BOOL)resetScoresAndGame {
    GameState *empty = [[GameState alloc] init];
    // Keep an empty v2 file rather than deleting it and allowing v1 re-import.
    // A failed write leaves the existing run and all records intact.
    if (![empty save]) return NO;
    _game = (HPGame){0};
    _hasRun = NO;
    [self resetTiming];
    [_bestRecords removeAllObjects];
    return YES;
}

- (BOOL)restoreRun:(id)run {
    HPGame game;
    long long elapsed;
    BOOL started, eligible;
    if (!HPReadGame(run, &game) ||
        !HPReadInteger(run[@"activeMilliseconds"], LLONG_MAX, &elapsed) ||
        !HPReadBoolean(run[@"timingStarted"], &started) ||
        !HPReadBoolean(run[@"timingEligible"], &eligible)) return NO;
    if ((!game.moves && (started || elapsed || !eligible)) ||
        (game.moves && !started) || (!eligible && elapsed)) return NO;
    NSDictionary *pending = run[@"pendingResult"];
    if (pending) {
        long long level, minimum;
        NSDictionary *record = HPReadRecord(pending, game.level);
        if (game.phase != HPLevelComplete || !eligible || !started || !record ||
            !HPReadInteger(pending[@"level"], HPLevelCount - 1, &level) || level != game.level ||
            !HPReadInteger(pending[@"minimum"], 1023, &minimum) || minimum != HPGameMinimumMoves(&game) ||
            [record[@"moves"] longLongValue] != game.moves ||
            [record[@"seconds"] longLongValue] != elapsed / 1000) return NO;
        pending = @{@"level": @(level), @"minimum": @(minimum),
                    @"seconds": record[@"seconds"], @"moves": record[@"moves"]};
    }
    _game = game;
    _hasRun = YES;
    _accumulatedMilliseconds = elapsed;
    _timingStarted = started;
    _timingEligible = eligible;
    _pendingResult = pending;
    // A valid pending result can repair its own separately damaged score entry.
    NSDictionary *best = [self recordForLevel:game.level];
    if (pending && (!best || [pending[@"seconds"] longLongValue] < [best[@"seconds"] longLongValue])) {
        _bestRecords[[NSString stringWithFormat:@"%d", game.level]] =
            @{@"seconds": pending[@"seconds"], @"moves": pending[@"moves"]};
    }
    return YES;
}

+ (instancetype)loadSavedGame {
    GameState *state = [[self alloc] init];
    NSURL *v2URL = [self saveURLForVersion:2];
    // Existence takes precedence even if v2 is damaged: never resurrect old v1 progress.
    if (v2URL && [[NSFileManager defaultManager] fileExistsAtPath:v2URL.path]) {
        NSDictionary *payload = HPReadPayload(v2URL);
        long long version;
        if (!HPReadInteger(payload[@"version"], 2, &version) || version != 2) return state;
        NSDictionary *records = payload[@"bestRecords"];
        if ([records isKindOfClass:[NSDictionary class]]) {
            for (int level = 0; level < HPLevelCount; ++level) {
                NSString *key = [NSString stringWithFormat:@"%d", level];
                NSDictionary *record = HPReadRecord(records[key], level);
                if (record) state->_bestRecords[key] = record;
            }
        }
        [state restoreRun:payload[@"run"]];
        return state;
    }
    NSDictionary *legacy = HPReadPayload([self saveURLForVersion:1]);
    long long version;
    HPGame game;
    if (!HPReadInteger(legacy[@"version"], 1, &version) || version != 1 || !HPReadGame(legacy, &game)) return state;
    state->_game = game;
    state->_hasRun = YES;
    [state resetTiming];
    state->_timingStarted = game.moves > 0;
    state->_timingEligible = game.moves == 0;
    if (game.phase == HPLevelComplete) {
        // v1 had no acknowledgement UI or recoverable elapsed time.
        HPGameAdvance(&state->_game);
        if (state->_game.phase == HPPlaying) [state resetTiming];
    }
    [state save];
    return state;
}

- (BOOL)save {
    NSMutableDictionary *payload = [@{@"version": @2, @"bestRecords": _bestRecords} mutableCopy];
    if (_hasRun) {
        if (!HPGameIsValid(&_game)) return NO;
        NSMutableArray *posts = [NSMutableArray arrayWithCapacity:HPPostCount];
        for (int post = 0; post < HPPostCount; ++post) {
            NSMutableArray *stack = [NSMutableArray arrayWithCapacity:_game.counts[post]];
            for (int i = 0; i < _game.counts[post]; ++i) [stack addObject:@(_game.disks[post][i])];
            [posts addObject:stack];
        }
        NSMutableDictionary *run = [@{@"level": @(_game.level), @"moves": @(_game.moves),
            @"totalMoves": @(_game.totalMoves), @"phase": @(_game.phase), @"posts": posts,
            @"activeMilliseconds": @(self.elapsedMilliseconds), @"timingStarted": @(_timingStarted),
            @"timingEligible": @(_timingEligible)} mutableCopy];
        if (_pendingResult) run[@"pendingResult"] = _pendingResult;
        payload[@"run"] = run;
    }
    NSURL *url = [GameState saveURLForVersion:2];
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
