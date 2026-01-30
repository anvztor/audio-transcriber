---
name: audio-transcriber
description: Voice transcriber with semantic error correction for homophonic words.
homepage: https://ai.google.dev/
metadata: {"clawdbot":{"emoji":"🎙️","requires":{"bins":["curl","ffmpeg","python3"],"env":["GEMINI_API_KEY"]},"primaryEnv":"GEMINI_API_KEY"}}
---

# Audio Transcriber Skill

Voice transcriber with **semantic error correction** for homophonic/homonym errors.

## Features

### 1. Automatic Transcription
- Uses Gemini 2.5 Flash API
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

### 3. Context-Aware Correction
- Checks user's workflow context
- Uses memory/known paths for better guesses
- Falls back to asking user if unclear

## Scripts

### Manual Transcription
```bash
/home/drej/clawd/skills/audio-transcriber/scripts/transcribe-and-correct.sh /path/to/audio.ogg
```

### Auto-Processor Service (6-second interval)
```bash
/home/drej/clawd/skills/audio-transcriber/scripts/voice-processor-service.sh
```

## Workflow

1. **Receive audio** → Telegram webhook or inbound folder
2. **Transcribe** → Gemini API
3. **Correct homophonic errors** → Python-based pattern matching
4. **Validate** → If unclear, ask user for clarification
5. **Execute** → Process the corrected command

## Fallback Behavior

If the corrected transcript is still unclear:
1. Log the ambiguous transcript
2. Ask user to rephrase
3. Store in memory for future reference

## Configuration

Custom corrections can be added in `transcribe-and-correct.sh`:

```python
corrections = {
    r'\bnew_word\b': 'corrected_word',
}
```

## Requirements

- `GEMINI_API_KEY` environment variable
- `ffmpeg` for audio conversion
- `python3` for error correction
