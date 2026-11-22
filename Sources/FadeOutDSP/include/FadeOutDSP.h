#ifndef FADE_OUT_DSP_H
#define FADE_OUT_DSP_H

#include <CoreAudio/CoreAudio.h>
#include <stdatomic.h>
#include <stdbool.h>

typedef struct {
    _Atomic(float) targetGain;
    float currentGain;
    _Atomic(bool) formatMismatch;
    UInt32 inputBufferOffset;
    UInt32 inputChannels;
    UInt32 outputChannels;
    bool inputNonInterleaved;
    bool outputNonInterleaved;
} FOGainState;

void FOGainInit(FOGainState * _Nonnull state, float gain);
void FOGainConfigure(FOGainState * _Nonnull state, UInt32 inputBufferOffset,
                     UInt32 inputChannels, bool inputNonInterleaved,
                     UInt32 outputChannels, bool outputNonInterleaved);
void FOGainSetTarget(FOGainState * _Nonnull state, float gain);
bool FOGainHasFormatMismatch(FOGainState * _Nonnull state);
void FOGainProcess(FOGainState * _Nonnull state, const float * _Nonnull source,
                   float * _Nonnull destination, unsigned int frames, unsigned int channels);
OSStatus FOGainIOProc(AudioObjectID device,
                      const AudioTimeStamp * _Nonnull now,
                      const AudioBufferList * _Nonnull input,
                      const AudioTimeStamp * _Nonnull inputTime,
                      AudioBufferList * _Nonnull output,
                      const AudioTimeStamp * _Nonnull outputTime,
                      void * _Nullable clientData);
OSStatus FONoopIOProc(AudioObjectID device,
                     const AudioTimeStamp * _Nonnull now,
                     const AudioBufferList * _Nonnull input,
                     const AudioTimeStamp * _Nonnull inputTime,
                     AudioBufferList * _Nonnull output,
                     const AudioTimeStamp * _Nonnull outputTime,
                     void * _Nullable clientData);

#endif
