#include "GameRules.h"
#include <limits.h>
#include <string.h>

int HPGameDiskCount(const HPGame *game) { return game->level + 3; }
int HPGameMinimumMoves(const HPGame *game) { return (1 << HPGameDiskCount(game)) - 1; }

void HPGameNew(HPGame *game) {
    memset(game, 0, sizeof(*game));
    game->counts[0] = 3;
    for (int i = 0; i < 3; ++i) game->disks[0][i] = i;
}

int HPGameIsValid(const HPGame *game) {
    if (!game || game->level < 0 || game->level >= HPLevelCount ||
        game->moves < 0 || game->totalMoves < game->moves ||
        game->phase < HPPlaying || game->phase > HPWon) return 0;
    long long previousMinimum = 0;
    for (int level = 0; level < game->level; ++level) previousMinimum += (1 << (level + 3)) - 1;
    if (game->totalMoves - game->moves < previousMinimum) return 0;
    if (game->level == 0 && game->totalMoves != game->moves) return 0;
    int seen = 0, n = HPGameDiskCount(game);
    for (int post = 0; post < HPPostCount; ++post) {
        if (game->counts[post] < 0 || game->counts[post] > n) return 0;
        int previous = -1;
        for (int i = 0; i < game->counts[post]; ++i) {
            int disk = game->disks[post][i];
            if (disk < 0 || disk >= n || disk <= previous || (seen & (1 << disk))) return 0;
            seen |= 1 << disk;
            previous = disk;
        }
    }
    if (seen != (1 << n) - 1) return 0;
    int solved = game->counts[2] == n;
    if ((game->phase == HPPlaying) == solved) return 0;
    if (solved && game->moves < HPGameMinimumMoves(game)) return 0;
    if (game->phase == HPWon && game->level != HPLevelCount - 1) return 0;
    if (!game->moves && game->counts[0] != n) return 0;
    return 1;
}

HPMoveResult HPGameMove(HPGame *game, int from, int to) {
    if (!HPGameIsValid(game) || game->phase != HPPlaying ||
        from < 0 || from >= HPPostCount || to < 0 || to >= HPPostCount || !game->counts[from]) return HPRejected;
    if (from == to) return HPSamePost;
    int disk = game->disks[from][game->counts[from] - 1];
    if (game->counts[to] && game->disks[to][game->counts[to] - 1] > disk) return HPRejected;
    if (game->moves == LLONG_MAX || game->totalMoves == LLONG_MAX) return HPRejected;
    --game->counts[from];
    game->disks[to][game->counts[to]++] = disk;
    ++game->moves;
    ++game->totalMoves;
    if (game->counts[2] == HPGameDiskCount(game)) {
        game->phase = HPLevelComplete;
        return HPCompleted;
    }
    return HPMoved;
}

int HPGameAdvance(HPGame *game) {
    if (!HPGameIsValid(game) || game->phase != HPLevelComplete) return 0;
    if (game->level == HPLevelCount - 1) {
        game->phase = HPWon;
    } else {
        ++game->level;
        game->moves = 0;
        game->phase = HPPlaying;
        memset(game->counts, 0, sizeof(game->counts));
        memset(game->disks, 0, sizeof(game->disks));
        game->counts[0] = HPGameDiskCount(game);
        for (int i = 0; i < game->counts[0]; ++i) game->disks[0][i] = i;
    }
    return 1;
}
