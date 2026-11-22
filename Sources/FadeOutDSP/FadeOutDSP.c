#include "FadeOutDSP.h"
#include <math.h>
#include <stddef.h>
#include <string.h>

void FOGainInit(FOGainState *state, float gain) {
    atomic_init(&state->targetGain, gain);
    state->currentGain = gain;
    atomic_init(&state->formatMismatch, false);
    state->inputBufferOffset = 0;
    state->inputChannels = 0;
    state->outputChannels = 0;
    state->inputNonInterleaved = false;
    state->outputNonInterleaved = false;
}

void FOGainConfigure(FOGainState *state, UInt32 inputBufferOffset,
                     UInt32 inputChannels, bool inputNonInterleaved,
                     UInt32 outputChannels, bool outputNonInterleaved) {
    state->inputBufferOffset = inputBufferOffset;
    state->inputChannels = inputChannels;
    state->outputChannels = outputChannels;
    state->inputNonInterleaved = inputNonInterleaved;
    state->outputNonInterleaved = outputNonInterleaved;
    atomic_store_explicit(&state->formatMismatch, false, memory_order_relaxed);
}

void FOGainSetTarget(FOGainState *state, float gain) {
    atomic_store_explicit(&state->targetGain, fmaxf(0.0f, fminf(gain, 1.5f)), memory_order_relaxed);
}

bool FOGainHasFormatMismatch(FOGainState *state) {
    return atomic_load_explicit(&state->formatMismatch, memory_order_relaxed);
}

void FOGainProcess(FOGainState *state, const float *source, float *destination,
                   unsigned int frames, unsigned int channels) {
    const float target = atomic_load_explicit(&state->targetGain, memory_order_relaxed);
    float current = state->currentGain;
    for (unsigned int frame = 0; frame < frames; ++frame) {
        current += (target - current) * (1.0f / 128.0f);
        for (unsigned int channel = 0; channel < channels; ++channel) {
            const unsigned int index = frame * channels + channel;
            destination[index] = source[index] * current;
        }
    }
    state->currentGain = current;
}

// HAL calls this on a real-time thread. Only stack values, atomics and sample writes are used.
// Duplex interfaces place their hardware input buffers before the process-tap buffers.
// Format metadata is prepared off the real-time thread so this callback can route the
// correct tap buffers without allocating, locking, or querying Core Audio.
OSStatus FOGainIOProc(AudioObjectID device,
                      const AudioTimeStamp *now,
                      const AudioBufferList *input,
                      const AudioTimeStamp *inputTime,
                      AudioBufferList *output,
                      const AudioTimeStamp *outputTime,
                      void *clientData) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    FOGainState *state = (FOGainState *)clientData;
    if (!state || !input || !output) {
        if (state) atomic_store_explicit(&state->formatMismatch, true, memory_order_relaxed);
        return noErr;
    }
    const UInt32 inputChannels = state->inputChannels;
    const UInt32 outputChannels = state->outputChannels;
    const UInt32 inputBuffersNeeded = state->inputNonInterleaved ? inputChannels : 1;
    const UInt32 outputBuffersNeeded = state->outputNonInterleaved ? outputChannels : 1;
    if (inputChannels == 0 || outputChannels == 0 ||
        input->mNumberBuffers < state->inputBufferOffset + inputBuffersNeeded ||
        output->mNumberBuffers < outputBuffersNeeded) {
        atomic_store_explicit(&state->formatMismatch, true, memory_order_relaxed);
        return noErr;
    }

    for (UInt32 i = 0; i < output->mNumberBuffers; ++i) {
        if (output->mBuffers[i].mData) {
            memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
        }
    }

    const AudioBuffer *firstInput = &input->mBuffers[state->inputBufferOffset];
    AudioBuffer *firstOutput = &output->mBuffers[0];
    const UInt32 inputBytesPerFrame = sizeof(float) * (state->inputNonInterleaved ? 1 : inputChannels);
    const UInt32 outputBytesPerFrame = sizeof(float) * (state->outputNonInterleaved ? 1 : outputChannels);
    if (!firstInput->mData || !firstOutput->mData || inputBytesPerFrame == 0 || outputBytesPerFrame == 0) {
        atomic_store_explicit(&state->formatMismatch, true, memory_order_relaxed);
        return noErr;
    }
    const UInt32 inputFrames = firstInput->mDataByteSize / inputBytesPerFrame;
    const UInt32 outputFrames = firstOutput->mDataByteSize / outputBytesPerFrame;
    const UInt32 frames = inputFrames < outputFrames ? inputFrames : outputFrames;
    if (frames == 0) return noErr;

    const float target = atomic_load_explicit(&state->targetGain, memory_order_relaxed);
    float current = state->currentGain;
    for (UInt32 frame = 0; frame < frames; ++frame) {
        current += (target - current) * (1.0f / 128.0f);
        for (UInt32 channel = 0; channel < outputChannels; ++channel) {
            const UInt32 sourceChannel = channel % inputChannels;
            const UInt32 srcBufferIndex = state->inputBufferOffset +
                (state->inputNonInterleaved ? sourceChannel : 0);
            const UInt32 dstBufferIndex = state->outputNonInterleaved ? channel : 0;
            const AudioBuffer *src = &input->mBuffers[srcBufferIndex];
            AudioBuffer *dst = &output->mBuffers[dstBufferIndex];
            if (!src->mData || !dst->mData) {
                atomic_store_explicit(&state->formatMismatch, true, memory_order_relaxed);
                return noErr;
            }
            const UInt32 srcIndex = state->inputNonInterleaved ? frame : frame * inputChannels + sourceChannel;
            const UInt32 dstIndex = state->outputNonInterleaved ? frame : frame * outputChannels + channel;
            ((float *)dst->mData)[dstIndex] = ((const float *)src->mData)[srcIndex] * current;
        }
    }
    state->currentGain = current;
    return noErr;
}

// Used only by the short-lived permission probe. Starting IO on an aggregate that
// contains a tap is the operation that asks macOS for System Audio Recording access.
OSStatus FONoopIOProc(AudioObjectID device,
                     const AudioTimeStamp *now,
                     const AudioBufferList *input,
                     const AudioTimeStamp *inputTime,
                     AudioBufferList *output,
                     const AudioTimeStamp *outputTime,
                     void *clientData) {
    (void)device; (void)now; (void)input; (void)inputTime;
    (void)output; (void)outputTime; (void)clientData;
    return noErr;
}
