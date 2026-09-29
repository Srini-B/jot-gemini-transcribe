#include "voiceiq_aec.h"

#include <vector>

#include "modules/audio_processing/include/audio_processing.h"

struct voiceiq_aec {
  webrtc::scoped_refptr<webrtc::AudioProcessing> apm;
  webrtc::StreamConfig stream;
  std::vector<int16_t> far_copy;
};

extern "C" voiceiq_aec *voiceiq_aec_create(int sample_rate) {
  if (sample_rate != 8000 && sample_rate != 16000 && sample_rate != 32000 && sample_rate != 48000) {
    return nullptr;
  }
  auto *aec = new voiceiq_aec{webrtc::AudioProcessingBuilder().Create(), webrtc::StreamConfig(sample_rate, 1), {}};
  webrtc::AudioProcessing::Config config;
  // Echo cancellation only. Gain control and noise suppression would change
  // the owner's voice, which the transcriber hears best untouched.
  config.echo_canceller.enabled = true;
  config.echo_canceller.mobile_mode = false;
  config.high_pass_filter.enabled = true;
  aec->apm->ApplyConfig(config);
  aec->far_copy.resize(aec->stream.num_frames());
  return aec;
}

extern "C" int voiceiq_aec_frame_samples(const voiceiq_aec *aec) {
  return static_cast<int>(aec->stream.num_frames());
}

extern "C" int voiceiq_aec_process(voiceiq_aec *aec, const int16_t *far_end, int16_t *microphone) {
  aec->far_copy.assign(far_end, far_end + aec->stream.num_frames());
  int status = aec->apm->ProcessReverseStream(aec->far_copy.data(), aec->stream, aec->stream, aec->far_copy.data());
  if (status != 0) return status;
  aec->apm->set_stream_delay_ms(0);
  return aec->apm->ProcessStream(microphone, aec->stream, aec->stream, microphone);
}

extern "C" double voiceiq_aec_erle_db(voiceiq_aec *aec) {
  return aec->apm->GetStatistics().echo_return_loss_enhancement.value_or(-1);
}

extern "C" int voiceiq_aec_delay_ms(voiceiq_aec *aec) {
  return aec->apm->GetStatistics().delay_ms.value_or(-1);
}

extern "C" void voiceiq_aec_destroy(voiceiq_aec *aec) { delete aec; }
