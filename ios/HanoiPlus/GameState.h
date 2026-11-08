#import <Foundation/Foundation.h>
#import "GameRules.h"

NS_ASSUME_NONNULL_BEGIN
@interface GameState : NSObject
@property (nonatomic, readonly) HPGame game;
@property (nonatomic, readonly) BOOL hasRun;
@property (nonatomic, readonly) BOOL timingStarted;
@property (nonatomic, readonly) BOOL timingEligible;
@property (nonatomic, readonly) long long elapsedMilliseconds;
// Extra record data for a new best. Every HPLevelComplete run awaits a choice,
// including ordinary results with no extra record data.
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, NSNumber *> *pendingResult;
// A missing/invalid run must not hide valid records.
+ (instancetype)loadSavedGame;
- (void)startNewGame;
- (nullable NSDictionary<NSString *, NSNumber *> *)recordForLevel:(NSInteger)level;
- (HPMoveResult)moveFrom:(NSInteger)from to:(NSInteger)to;
- (BOOL)restart;
// Acknowledgement and the next board/final state are one atomic write.
// Failure restores the solved run and its pending result in memory.
- (BOOL)advanceAndSave;
// Keep all records while atomically replacing any solved run with a waiting
// attempt on the same level. Failure retains the solved result.
- (BOOL)restartCompletedLevelAndSave;
// Persist an empty v2 store before clearing memory, preventing v1 resurrection.
- (BOOL)resetScoresAndGame;
- (void)resumeTiming;
- (void)pauseTiming;
- (BOOL)save;
@end
NS_ASSUME_NONNULL_END
