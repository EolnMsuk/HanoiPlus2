#include "GameDuration.h"
#include <stdio.h>

void HPFormatDuration(long long seconds, char output[HPDurationBufferSize]) {
    if (seconds < 0) seconds = 0;
    if (seconds < 3600) {
        snprintf(output, HPDurationBufferSize, "%02lld:%02lld", seconds / 60, seconds % 60);
    } else {
        snprintf(output, HPDurationBufferSize, "%02lld:%02lld:%02lld",
                 seconds / 3600, seconds / 60 % 60, seconds % 60);
    }
}
