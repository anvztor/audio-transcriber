#!/bin/bash
# Voice command auto-detector and processor
# Place this in your cron or check periodically

AUDIO_DIR="/home/drej/.clawdbot/media/inbound"
PROCESSED_DIR="/home/drej/.clawdbot/media/processed"
LOG_FILE="/tmp/voice_processor.log"

mkdir -p "$PROCESSED_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Find new audio files
for audio_file in "$AUDIO_DIR"/*.ogg "$AUDIO_DIR"/*.m4a "$AUDIO_DIR"/*.mp3 "$AUDIO_DIR"/*.wav; do
    [ -f "$audio_file" ] || continue
    
    filename=$(basename "$audio_file")
    
    # Skip if already processed
    if [ -f "$PROCESSED_DIR/$filename.processed" ]; then
        continue
    fi
    
    log "Found new audio: $filename"
    
    # Transcribe using Gemini
    transcript=$(/home/drej/clawd/skills/audio-transcriber/scripts/transcribe-and-process.sh "$audio_file" 2>/dev/null)
    
    if [ -n "$transcript" ]; then
        log "Transcript: $transcript"
        
        # Save transcript
        echo "$transcript" > "$PROCESSED_DIR/$filename.txt"
        echo "processed" > "$PROCESSED_DIR/$filename.processed"
        
        # Move original audio
        mv "$audio_file" "$PROCESSED_DIR/" 2>/dev/null
        
        log "Processed: $filename -> $transcript"
        
        # Output for agent to pick up
        echo "=== VOICE COMMAND ==="
        echo "$transcript"
        echo "====================="
    fi
done
