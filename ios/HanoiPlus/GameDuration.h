#ifndef HP_GAME_DURATION_H
#define HP_GAME_DURATION_H

// Shared by the elapsed clock, results and score list. Output includes the NUL.
enum { HPDurationBufferSize = 32 };
void HPFormatDuration(long long seconds, char output[HPDurationBufferSize]);

#endif
