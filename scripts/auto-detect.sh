#!/bin/bash
# Voice command auto-detector and processor (one-shot)
# Use this for cron or periodic checks

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOME_DIR="${HOME:-/tmp}"
CLAWDBOT_HOME="${CLAWDBOT_HOME:-$HOME_DIR/.clawdbot}"
TMPDIR_DEFAULT="${TMPDIR:-/tmp}"

AUDIO_DIR="${AUDIO_DIR:-$CLAWDBOT_HOME/media/inbound}"
PROCESSED_DIR="${PROCESSED_DIR:-$CLAWDBOT_HOME/media/processed}"
LOG_FILE="${LOG_FILE:-$TMPDIR_DEFAULT/voice_processor.log}"

mkdir -p "$PROCESSED_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Find and process new audio files
for audio_file in "$AUDIO_DIR"/*.ogg "$AUDIO_DIR"/*.m4a "$AUDIO_DIR"/*.mp3 "$AUDIO_DIR"/*.wav; do
    [[ -f "$audio_file" ]] || continue

    filename=$(basename "$audio_file")

    # Skip if already processed
    if [[ -f "$PROCESSED_DIR/$filename.processed" ]]; then
        continue
    fi

    log "Found new audio: $filename"

    # Transcribe with correction using optimized script
    transcript=$("$SCRIPT_DIR/transcribe-and-correct.sh" "$audio_file" 2>/dev/null)

    if [[ -n "$transcript" ]]; then
        log "Transcript: $transcript"

        # Save transcript
        echo "$transcript" > "$PROCESSED_DIR/$filename.txt"
        echo "processed" > "$PROCESSED_DIR/$filename.processed"

        # Move original audio
        mv "$audio_file" "$PROCESSED_DIR/" 2>/dev/null || true

        log "Processed: $filename"

        # Output for agent to pick up
        echo "=== VOICE COMMAND ==="
        echo "$transcript"
        echo "====================="
    else
        log "Failed to transcribe: $filename"
    fi
done
