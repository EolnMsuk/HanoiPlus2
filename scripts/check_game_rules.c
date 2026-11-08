// Focused checks of the production C model; no iOS SDK or test framework.
#include "GameRules.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

static void solve(HPGame *game, int count, int from, int to, int spare) {
    if (!count) return;
    solve(game, count - 1, from, spare, to);
    HPMoveResult result = HPGameMove(game, from, to);
    assert(result == HPMoved || result == HPCompleted);
    assert(HPGameIsValid(game));
    solve(game, count - 1, spare, to, from);
}

int main(void) {
    HPGame game, before, corrupt;
    HPGameNew(&game);
    assert(HPGameIsValid(&game));
    before = game;
    assert(HPGameMove(&game, 0, 0) == HPSamePost);
    assert(HPGameMove(&game, 1, 2) == HPRejected);
    assert(HPGameMove(&game, -1, 2) == HPRejected);
    assert(!memcmp(&game, &before, sizeof(game)));
    assert(HPGameMove(&game, 0, 2) == HPMoved);
    assert(game.disks[2][0] == 2 && game.moves == 1 && game.totalMoves == 1);
    before = game;
    assert(HPGameMove(&game, 0, 2) == HPRejected); // Larger onto smaller.
    assert(!memcmp(&game, &before, sizeof(game)));
    corrupt = game;
    corrupt.disks[2][0] = 0; // Duplicate and missing disk.
    assert(!HPGameIsValid(&corrupt));
    corrupt = game;
    corrupt.counts[1] = 11;
    assert(!HPGameIsValid(&corrupt));
    corrupt = game;
    corrupt.phase = HPWon;
    assert(!HPGameIsValid(&corrupt));
    corrupt = game;
    corrupt.moves = -1;
    assert(!HPGameIsValid(&corrupt));
    corrupt = game;
    corrupt.moves = LLONG_MAX;
    corrupt.totalMoves = LLONG_MAX;
    assert(HPGameIsValid(&corrupt));
    before = corrupt;
    assert(HPGameMove(&corrupt, 2, 1) == HPRejected);
    assert(!memcmp(&corrupt, &before, sizeof(before)));
    HPGameNew(&game);
    for (int level = 0; level < HPLevelCount; ++level) {
        assert(game.level == level && game.moves == 0);
        assert(!HPGameAdvance(&game)); // Cannot skip an unsolved puzzle.
        solve(&game, HPGameDiskCount(&game), 0, 2, 1);
        assert(game.moves == HPGameMinimumMoves(&game));
        assert(game.phase == HPLevelComplete);
        // A stable save is the model snapshot, including completion pending.
        HPGame restored = game;
        assert(HPGameIsValid(&restored));
        assert(HPGameMove(&restored, 2, 0) == HPRejected);
        assert(HPGameAdvance(&restored));
        assert(!HPGameAdvance(&restored)); // Never advance twice.
        assert(HPGameIsValid(&restored));
        game = restored;
    }
    assert(game.phase == HPWon && game.totalMoves == 2032 && game.moves == 1023);
    corrupt = game;
    corrupt.totalMoves = corrupt.moves; // Earlier levels cannot vanish from total.
    assert(!HPGameIsValid(&corrupt));
    puts("Production rules: 8 levels / 2032 optimal moves, illegal and same-post drops, save invariants, overflow and single advancement passed.");
    return 0;
}
