// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// C interface to WebRTC's AEC3 echo canceller, for offline use on a recorded
// microphone track with the recorded system output as the far-end reference.

#ifndef VOICEIQ_AEC_H
#define VOICEIQ_AEC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct voiceiq_aec voiceiq_aec;

/// Mono 16-bit PCM at `sample_rate` (8000, 16000, 32000, or 48000). Returns
/// NULL for an unsupported rate.
voiceiq_aec *voiceiq_aec_create(int sample_rate);

/// Samples per call: 10 ms of audio.
int voiceiq_aec_frame_samples(const voiceiq_aec *aec);

/// Feeds one frame of the far end, then cancels its echo from one frame of
/// the microphone in place. Returns 0 on success.
int voiceiq_aec_process(voiceiq_aec *aec, const int16_t *far_end, int16_t *microphone);

/// Echo return loss enhancement in dB, or -1 when not yet known.
double voiceiq_aec_erle_db(voiceiq_aec *aec);

/// The canceller's current estimate of the far-end-to-microphone delay, or -1.
int voiceiq_aec_delay_ms(voiceiq_aec *aec);

void voiceiq_aec_destroy(voiceiq_aec *aec);

#ifdef __cplusplus
}
#endif

#endif
