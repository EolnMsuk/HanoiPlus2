#ifndef HP_GAME_RULES_H
#define HP_GAME_RULES_H

// Independent production model. Disk 0 is largest; stacks are bottom to top.
enum { HPPostCount = 3, HPLevelCount = 8, HPMaxDisks = 10 };
typedef enum { HPPlaying = 0, HPLevelComplete = 1, HPWon = 2 } HPPhase;
typedef enum { HPRejected = 0, HPSamePost, HPMoved, HPCompleted } HPMoveResult;
typedef struct {
    int level;
    long long moves;
    long long totalMoves; // Includes the current level, incremented once per move.
    HPPhase phase;
    int counts[HPPostCount];
    int disks[HPPostCount][HPMaxDisks];
} HPGame;

void HPGameNew(HPGame *game);
int HPGameDiskCount(const HPGame *game);
int HPGameMinimumMoves(const HPGame *game);
int HPGameIsValid(const HPGame *game);
HPMoveResult HPGameMove(HPGame *game, int from, int to);
int HPGameAdvance(HPGame *game);

#endif
