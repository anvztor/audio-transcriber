#!/bin/bash
# Voice processor service - watches for audio files and transcribes them
# Optimized: uses inotify for instant detection, fallback to polling

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOME_DIR="${HOME:-/tmp}"
CLAWDBOT_HOME="${CLAWDBOT_HOME:-$HOME_DIR/.clawdbot}"
TMPDIR_DEFAULT="${TMPDIR:-/tmp}"

AUDIO_DIR="${AUDIO_DIR:-$CLAWDBOT_HOME/media/inbound}"
PROCESSED_DIR="${PROCESSED_DIR:-$CLAWDBOT_HOME/media/processed}"
LOG_FILE="${LOG_FILE:-$TMPDIR_DEFAULT/voice_processor.log}"
POLL_INTERVAL="${POLL_INTERVAL:-6}"
MAX_CONCURRENT="${MAX_CONCURRENT:-3}"

mkdir -p "$PROCESSED_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

process_audio_file() {
    local audio_file="$1"
    local filename
    filename=$(basename "$audio_file")

    # Skip if already processed
    if [[ -f "$PROCESSED_DIR/$filename.processed" ]]; then
        return 0
    fi

    # Create lock file to prevent double processing
    local lock_file="$TMPDIR_DEFAULT/.processing_$filename.lock"
    if ! mkdir "$lock_file" 2>/dev/null; then
        return 0  # Another process is handling this file
    fi

    log "Processing: $filename"

    # Transcribe with semantic correction
    local transcript
    transcript=$("$SCRIPT_DIR/transcribe-and-correct.sh" "$audio_file" 2>/dev/null)

    if [[ -n "$transcript" ]]; then
        log "Transcript: $transcript"
        echo "$transcript" > "$PROCESSED_DIR/$filename.txt"
        echo "processed" > "$PROCESSED_DIR/$filename.processed"
        mv "$audio_file" "$PROCESSED_DIR/" 2>/dev/null || true
        log "Completed: $filename"

        # Output for agent
        echo "=== VOICE COMMAND ==="
        echo "$transcript"
        echo "====================="
    else
        log "Failed: $filename"
    fi

    # Remove lock
    rmdir "$lock_file" 2>/dev/null || true
}

process_all_files() {
    local count=0
    for audio_file in "$AUDIO_DIR"/*.ogg "$AUDIO_DIR"/*.m4a "$AUDIO_DIR"/*.mp3 "$AUDIO_DIR"/*.wav; do
        [[ -f "$audio_file" ]] || continue

        local filename
        filename=$(basename "$audio_file")
        [[ -f "$PROCESSED_DIR/$filename.processed" ]] && continue

        # Process in background if under limit
        if [[ $count -lt $MAX_CONCURRENT ]]; then
            process_audio_file "$audio_file" &
            ((count++))
        else
            # Wait for a slot
            wait -n 2>/dev/null || true
            process_audio_file "$audio_file" &
        fi
    done

    # Wait for all background jobs
    wait
}

# Check if inotifywait is available
use_inotify() {
    command -v inotifywait &>/dev/null
}

# Inotify-based watching (instant detection)
watch_with_inotify() {
    log "Starting inotify watcher on $AUDIO_DIR"

    # Process any existing files first
    process_all_files

    # Watch for new files
    inotifywait -m -e create -e moved_to --format '%f' "$AUDIO_DIR" 2>/dev/null | while read -r filename; do
        local ext="${filename##*.}"
        case "$ext" in
            ogg|m4a|mp3|wav)
                # Small delay to ensure file is fully written
                sleep 0.5
                process_audio_file "$AUDIO_DIR/$filename"
                ;;
        esac
    done
}

# Polling-based watching (fallback)
watch_with_polling() {
    log "Starting polling watcher (interval: ${POLL_INTERVAL}s)"

    while true; do
        process_all_files
        sleep "$POLL_INTERVAL"
    done
}

# Main entry point
main() {
    log "Voice processor service starting"
    log "Audio directory: $AUDIO_DIR"
    log "Processed directory: $PROCESSED_DIR"

    if use_inotify; then
        watch_with_inotify
    else
        log "inotifywait not available, using polling"
        watch_with_polling
    fi
}

# Handle graceful shutdown
trap 'log "Service stopping"; exit 0' SIGTERM SIGINT

main
