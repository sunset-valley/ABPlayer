# 0010 — Transcription Media Extraction Flow

## Summary

ABPlayer transcription no longer depends on an external FFmpeg binary. Audio inputs are transcribed directly, and video inputs are converted to a temporary WAV file in-process with AVFoundation before WhisperKit runs.

## Details

### Current Behavior

- Queue entry starts at `TranscriptionQueueManager.enqueue(...)` and runs one task at a time.
- `TranscriptionManager.transcribe(...)` is the orchestration entrypoint for model loading, extraction, and transcription.
- Model download/load uses the configured endpoint from `TranscriptionSettings.effectiveDownloadEndpoint`.

### Media Handling Path

1. `TranscriptionManager.transcribe(...)` receives a user-selected media URL.
2. The method checks whether the asset contains video tracks.
3. If the input is audio-only, the original URL is passed to WhisperKit directly.
4. If the input contains video, `extractAudio(from:)` converts the first audio track to mono 16 kHz PCM WAV.
5. The extracted temporary WAV path is passed to WhisperKit for transcription.
6. Temporary extraction output is removed after completion, failure, or cancellation.

### Extraction Implementation Notes

- Extraction uses `AVURLAsset`, `AVAssetReader`, and `AVAssetReaderTrackOutput`.
- Output is written through `AVAudioFile` with linear PCM settings expected by the transcription pipeline.
- Work runs on a detached background task; UI state updates remain on `@MainActor`.
- The app does not spawn external media conversion subprocesses for transcription.

### User-Facing Settings That Matter

`TranscriptionSettings` currently controls:

- model selection
- language selection
- model directory
- auto-transcribe toggle
- pause-on-word-dismiss toggle
- transcription download endpoint/mirror

There is no FFmpeg path, download, or binary management setting.

## Related Docs

- [ABPlayer architecture overview](./0001_project-structure.md)
- [Code quality observations and technical debt](./0002_code-quality-and-tech-debt.md)
- [macOS distribution compliance checklist](../mem-backbone/0003_macos-distribution-compliance.md)
