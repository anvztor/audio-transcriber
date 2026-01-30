---
name: audio-transcriber
description: Voice transcriber with semantic error correction for homophonic words.
homepage: https://ai.google.dev/
metadata: {"clawdbot":{"emoji":"🎙️","requires":{"bins":["curl","ffmpeg","python3","jq"],"env":["GEMINI_API_KEY"]},"primaryEnv":"GEMINI_API_KEY"}}
---

# Audio Transcriber Skill

Voice transcriber with **semantic error correction** for homophonic/homonym errors.

## Features

### 1. Optimized Transcription
- Uses Gemini 2.5 Flash API with enhanced prompts
- Audio caching to avoid redundant conversions
- Automatic retry with exponential backoff
- Supports `.ogg`, `.m4a`, `.mp3`, `.wav`

### 2. Homophonic Error Correction
Detects and corrects common speech recognition errors:

| Original (Speech) | Corrected (Intent) |
|------------------|-------------------|
| cloudboot | clawdbot |
| pro system | processed |
| cloud bot | clawdbot |
| process system | processed |
| AMVZ / AVZ / AMZ | anvz (user directory) |
| 帮你 | 帮我 |

### 3. User-Configurable Vocabulary
Custom corrections in `~/.clawdbot/config/vocabulary.json`:

```json
{
    "known_terms": ["clawdbot", "anvz", "processed"],
    "corrections": {
        "\\bmy_term\\b": "corrected_term"
    },
    "language_hints": ["zh-CN", "en-US"]
}
```

### 4. Instant File Detection
- Uses inotify for instant audio file detection (Linux)
- Fallback to 6-second polling if inotify unavailable
- Parallel processing support (up to 3 concurrent files)

## Scripts

### Basic Transcription
```bash
./scripts/transcribe.sh audio.ogg
./scripts/transcribe.sh audio.ogg --simple  # Faster, minimal prompt
./scripts/transcribe.sh audio.ogg --model gemini-2.0-flash
```

### Transcription with Correction
```bash
./scripts/transcribe-and-correct.sh audio.ogg
./scripts/transcribe-and-correct.sh audio.ogg --show-original  # Show original text
```

### Intent Analysis
```bash
./scripts/voice-command.sh audio.ogg
./scripts/voice-command.sh audio.ogg --context "user is in /home/drej"
```

### Voice Command Execution
```bash
./scripts/execute-voice.sh audio.ogg
./scripts/execute-voice.sh audio.ogg --dry-run  # Preview without executing
```

### Auto-Processor Service
```bash
./scripts/voice-processor-service.sh  # Daemon mode
./scripts/auto-detect.sh              # One-shot processing
```

## Architecture

```
scripts/
├── lib/
│   ├── convert-audio.sh   # Audio conversion with caching
│   ├── gemini-client.sh   # API client with retry logic
│   ├── prompts.sh         # Optimized prompts
│   └── corrections.py     # Semantic error correction
├── transcribe.sh
├── transcribe-and-correct.sh
├── voice-command.sh
├── execute-voice.sh
├── auto-detect.sh
└── voice-processor-service.sh
```

## Performance Optimizations

1. **Audio Caching**: MD5-based cache avoids re-converting same files
2. **Optimized FFmpeg**: Uses `-q:a 5` preset for faster encoding
3. **Retry Logic**: Exponential backoff (1s, 2s, 4s) for API failures
4. **Parallel Processing**: Up to 3 concurrent transcriptions
5. **inotify Watching**: Instant file detection (no polling delay)

## Requirements

- `GEMINI_API_KEY` environment variable
- `ffmpeg` for audio conversion
- `python3` for error correction
- `jq` for JSON processing
- `curl` for API calls
- `inotify-tools` (optional, for instant detection)

## Testing

Run benchmarks:
```bash
./tests/benchmark.sh
```

Run unit tests (requires bats):
```bash
bats tests/unit/
```
