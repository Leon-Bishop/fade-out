#include "FadeOutDSP.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    FOGainState state;
    FOGainInit(&state, 1.0f);
    FOGainConfigure(&state, 0, 2, false, 2, true);
    const float interleaved[] = {1.0f, 2.0f, 3.0f, 4.0f};
    float left[] = {0.0f, 0.0f};
    float right[] = {0.0f, 0.0f};
    struct { UInt32 count; AudioBuffer buffers[1]; } input = {
        1, {{2, sizeof(interleaved), (void *)interleaved}}
    };
    struct { UInt32 count; AudioBuffer buffers[2]; } output = {
        2, {{1, sizeof(left), left}, {1, sizeof(right), right}}
    };
    AudioTimeStamp time = {0};
    FOGainIOProc(0, &time, (const AudioBufferList *)&input, &time,
                 (AudioBufferList *)&output, &time, &state);
    assert(left[0] == 1.0f && left[1] == 3.0f);
    assert(right[0] == 2.0f && right[1] == 4.0f);
    assert(!state.formatMismatch);
    puts("Planar/interleaved routing: passed");

    // A duplex interface contributes hardware input buffers before the stereo tap,
    // and may expose more output channels than the tapped app.
    const float hardwareInput[] = {9.0f, 9.0f};
    const float tap[] = {1.0f, 2.0f};
    float multichannel[] = {0.0f, 0.0f, 0.0f, 0.0f};
    struct { UInt32 count; AudioBuffer buffers[2]; } duplexInput = {
        2, {{1, sizeof(hardwareInput), (void *)hardwareInput},
            {2, sizeof(tap), (void *)tap}}
    };
    struct { UInt32 count; AudioBuffer buffers[1]; } duplexOutput = {
        1, {{4, sizeof(multichannel), multichannel}}
    };
    FOGainInit(&state, 1.0f);
    FOGainConfigure(&state, 1, 2, false, 4, false);
    FOGainIOProc(0, &time, (const AudioBufferList *)&duplexInput, &time,
                 (AudioBufferList *)&duplexOutput, &time, &state);
    assert(multichannel[0] == 1.0f && multichannel[1] == 2.0f);
    assert(multichannel[2] == 1.0f && multichannel[3] == 2.0f);
    assert(!state.formatMismatch);
    puts("Duplex multichannel routing: passed");
    return 0;
}
