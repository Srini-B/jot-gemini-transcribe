# 2026-09-27: Meeting transcription, speakers, and notes rebuilt

## Why

The user found meeting notes misclassified and asked for the rules popular open-source meeting apps send to the model, including FluidVoice's new meeting feature. They then asked to apply the research, with four requirements. The model should choose the meeting format itself, without a template picker. Meetings of one or two hours must work on a Tier 1 Gemini key. Speakers must stay correct across chunks. OpenRouter and Vercel must work too, since OpenRouter is the active provider.

## Findings

- FluidVoice's summary prompt is not public. It lives behind a `PRIVATE_AI_PROVIDER` compile flag. Its public code keeps the mic and app-audio tracks apart and holds speaker state across the whole track. That design shaped this change.
- The 30.6-minute Tamil Meet recording from 2026-09-26 (`3866E6B6`) was the test case. Its system track sat near −60 dBFS for most speech. The old code averaged the two tracks, which made the far side even quieter.
- Gemini's labels (`spk:0`) reset in every request, and the old code merged them across chunks. The gateways have no diarizing transcription endpoint at all. OpenRouter returned one untimed segment whatever options were sent.
- Tier 1 `gemini-3.5-transcribe` allows 10,000 input tokens a minute, or about 400 s of audio. A single larger request is still accepted, and the next one then waits.

## Decisions

- **One timeline, levelled, mic ducked under the far side.** Transcribing each track on its own was tried and dropped. Requests holding only the far side, with its silences cut out, returned a fraction of the speech on both models.
- **Reference clips for speaker continuity.** Every window carries up to 20 s of each known speaker. This was chosen over voice embeddings because the product rules out local models. Tested on a synthetic four-person call: one 8 s clip per speaker linked 60% of turns, and 20 s linked 100%.
- **Native path:** the clips sit inside the audio, and the API's labels on them map ids. **Gateway path:** `gemini-3.8-flash` gets the clips as separate audio parts and answers with the ids. The flash model's timestamps drifted too much for the native path's overlap vote.
- **"You" from the tracks, not the model.** A label heard at least twice as much from the mic alone as from the far side becomes `you`, both per window and over the whole meeting.
- **Windows of 600 s of speech on Google, 150 s on gateways.** Finished windows are cached. Throttles move a window to the next provider with a key, and when every provider is throttled the transcriber waits up to 45 minutes.
- **Meeting type chosen by the model** from `MeetingKind` (14 types, each with its sections). The notes model also suggests speaker names, but only from a self-introduction or repeated direct address.
- The prompt drops secrets read aloud. The Tamil call read out passwords and OTPs.

## Verification

Each run used the real APIs, through a temporary opt-in XCTest probe on copies of the recordings. The probe was deleted afterwards.

- Synthetic four-person call, four 60 s windows: every speaker kept one id. Turns were 98% correct on Google's endpoint and 89% through OpenRouter. The notes came back as `status_update`, with every owner, deadline, and self-introduced name correct, and the launch-date decision separated from the open discount question.
- Tamil call through OpenRouter: 807 words across the owner, the trainee, and a third voice. The notes came back as `training` with a Tamil title (two runs).
- Tamil call on Google, Tier 1: two windows, with 11 s and 53 s rate-limit waits between them. The run returned 907 words and completed in 126 s.
- `swift test --package-path VoiceIQCore`: 193 tests, 9 skipped, 0 failures, after the probe was removed. `./scripts/build.sh` succeeded.
- Owner talking over the far side: a synthetic call with four interjections came back with 3 to 5 of 8 to 10 words on Google's endpoint. The words were attributed to the remote speaker, while the rest of the call stayed at 100% correct turns. An adaptive duck was also tried. It kept the mic at full level whenever it was 10 dB above the measured echo coupling, and it dropped correct turns to 73% without recovering more words, so it was reverted. Interjections over the far side remain a known weak spot.
- Not verified: the new Meetings UI (type label, sections, Redo menu, speaker chips) was compiled but not driven in the running app, and no meeting longer than 31 minutes was tested.

## Rollback

Revert the commit. Recordings are unaffected. Transcripts and notes written by this version carry extra optional fields that the older code ignores. Cached windows sit in `transcribe-v4-*` folders beside the audio and can be deleted.
