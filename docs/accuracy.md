# Transcription accuracy investigation

This comparison describes the public Warp source inspected on 30 October 2026 and this project's current implementation. It does not establish what model is used behind Warp's server or explain a particular dictation error.

## What matches

- Warp's [`ServerVoiceTranscriber`](https://github.com/warpdotdev/warp/blob/master/app/src/server/voice_transcriber.rs) sends a request with `provider: Wispr`, base64 WAV audio and an optional language. This project sends `provider: wispr`, audio, and no language by default to the same `/ai/transcribe` path.
- The public [Warp voice input implementation](https://github.com/warpdotdev/warp/blob/master/crates/voice_input/src/lib.rs) produces mono, 16 kHz, 16-bit PCM WAV. This project requests the same format from `AVAudioRecorder`.
- Both use the default microphone, but the device and system processing must still be verified during an actual paired test.

## What differs or is unknown

- Warp uses CPAL for capture and explicitly downmixes and resamples with a sinc resampler; this app uses macOS `AVAudioRecorder` and its conversion path. Their waveforms may differ even at the same sample rate.
- Warp begins its own recording when its hotkey activates. Here, the app waits about 300 ms to distinguish a short key press, then starts the recorder. Speech started immediately may be clipped; recorder startup can add more delay.
- Warp can send a configured language; this app currently requests automatic detection. The settings may differ on a particular machine.
- Warp's source inserts the returned transcript; no separate cleanup step is visible in that path. The server's provider/model version, server-side processing and configuration remain opaque. Same provider and endpoint do not prove identical model or processing.
- We have not captured or compared the same real utterance in both applications, nor measured recognition error rates, onset latency, input levels or the selected input device. The earlier 1.35–1.53 second tests used synthesized speech and only measured the server request.

## Suggested controlled comparison

Use the same microphone, environment and Russian phrases (including technical terms). Wait for the recording indicator before speaking. Compare at least 10 utterances of different lengths against a manually checked reference and record word error rates. For an isolated server test, submit the same consented WAV through both clients with matching language and workspace settings. Review privacy and usage implications before retaining or transmitting recordings. Avoid logging sensitive speech or transcript text by default.
