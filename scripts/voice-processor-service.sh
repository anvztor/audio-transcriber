#!/bin/bash
# Voice processor service - runs every 6 seconds
# Enhanced with semantic error correction

AUDIO_DIR="/home/drej/.clawdbot/media/inbound"
PROCESSED_DIR="/home/drej/.clawdbot/media/processed"
LOG_FILE="/tmp/voice_processor.log"

mkdir -p "$PROCESSED_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

while true; do
    for audio_file in "$AUDIO_DIR"/*.ogg "$AUDIO_DIR"/*.m4a "$AUDIO_DIR"/*.mp3 "$AUDIO_DIR"/*.wav; do
        [ -f "$audio_file" ] || continue
        
        filename=$(basename "$audio_file")
        
        if [ -f "$PROCESSED_DIR/$filename.processed" ]; then
            continue
        fi
        
        log "Found new audio: $filename"
        
        # Use enhanced transcriber with semantic correction
        transcript=$(/home/drej/clawd/skills/audio-transcriber/scripts/transcribe-and-correct.sh "$audio_file" 2>/dev/null)
        
        if [ -n "$transcript" ]; then
            log "Transcript: $transcript"
            echo "$transcript" > "$PROCESSED_DIR/$filename.txt"
            echo "processed" > "$PROCESSED_DIR/$filename.processed"
            mv "$audio_file" "$PROCESSED_DIR/" 2>/dev/null
            log "Processed: $filename"
            
            # Output for agent
            echo "=== VOICE COMMAND ==="
            echo "$transcript"
            echo "====================="
        fi
    done
    sleep 6
done
