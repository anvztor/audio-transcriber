#!/bin/bash
# Transcribe audio and return text for agent to process

AUDIO_FILE="$1"
OUTPUT_DIR="/tmp"

[[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]] && exit 1
[[ -z "$GEMINI_API_KEY" ]] && exit 1

# Convert to MP3
ffmpeg -y -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a libmp3lame "$OUTPUT_DIR/voice_tmp.mp3" 2>/dev/null

# Transcribe
AUDIO_DATA=$(base64 -w0 "$OUTPUT_DIR/voice_tmp.mp3")

RESPONSE=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"contents\": [{
            \"parts\": [
                {\"text\": \"请将这段音频转录成文字，只输出文字内容\"},
                {\"inlineData\": {\"mimeType\": \"audio/mpeg\", \"data\": \"$AUDIO_DATA\"}}
            ]
        }]
    }")

rm -f "$OUTPUT_DIR/voice_tmp.mp3"

# Return transcribed text
echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null
