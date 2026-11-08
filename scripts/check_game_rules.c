// Focused checks of the production C model; no iOS SDK or test framework.
#include "GameRules.h"
#include "GameDuration.h"
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
    assert(HPGameRestart(&game));
    assert(HPGameIsValid(&game) && game.moves == 0 && game.totalMoves == 0);
    assert(HPGameRestart(&game)); // A waiting attempt can be restarted safely.
    assert(HPGameMove(&game, 0, 2) == HPMoved);
    assert(game.disks[2][0] == 2 && game.moves == 1 && game.totalMoves == 1);
    before = game;
    assert(HPGameMove(&game, 0, 2) == HPRejected); // Larger onto smaller.
    assert(!memcmp(&game, &before, sizeof(game)));
    corrupt = game;
    corrupt.disks[2][0] = 0; // Duplicate and missing disk.
    assert(!HPGameIsValid(&corrupt));
    before = corrupt;
    assert(!HPGameRestart(&corrupt));
    assert(!memcmp(&corrupt, &before, sizeof(corrupt)));
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
    solve(&game, 3, 0, 2, 1);
    before = game;
    assert(!HPGameRestart(&game)); // A solved result must be acknowledged.
    assert(!memcmp(&game, &before, sizeof(game)));
    assert(HPGameAdvance(&game));
    assert(HPGameMove(&game, 0, 1) == HPMoved);
    assert(HPGameMove(&game, 0, 2) == HPMoved);
    assert(game.level == 1 && game.moves == 2 && game.totalMoves == 9);
    assert(HPGameRestart(&game));
    assert(HPGameIsValid(&game) && game.level == 1 && game.moves == 0 && game.totalMoves == 7);
    assert(game.counts[0] == 4 && game.counts[1] == 0 && game.counts[2] == 0);
    for (int i = 0; i < 4; ++i) assert(game.disks[0][i] == i);
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
    const long long seconds[] = {0, 1, 59, 60, 61, 3599, 3600, 3661};
    const char *expected[] = {"00:00", "00:01", "00:59", "01:00", "01:01", "59:59", "01:00:00", "01:01:01"};
    for (int i = 0; i < (int)(sizeof(seconds) / sizeof(seconds[0])); ++i) {
        char duration[HPDurationBufferSize];
        HPFormatDuration(seconds[i], duration);
        assert(!strcmp(duration, expected[i]));
    }
    puts("Production rules: 8 levels / 2032 optimal moves, illegal/same-post drops, invariants, overflow, single advancement and restart totals passed.");
    puts("Duration formatter: 0, 1, 59, 60, 61, 3599, 3600 and 3661 seconds passed.");
    return 0;
}
