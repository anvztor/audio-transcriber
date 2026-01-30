#!/bin/bash
# Audio transcription script using Gemini API

set -e

AUDIO_FILE=""
MODEL="gemini-2.5-flash"
OUTPUT_DIR="/tmp"

usage() {
    echo "Usage: $0 <audio_file> [--model <name>] [--out <dir>]"
    echo "Example: $0 audio.ogg --model gemini-2.0-flash"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            MODEL="$2"
            shift 2
            ;;
        --out)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            AUDIO_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$AUDIO_FILE" ]]; then
    usage
fi

if [[ ! -f "$AUDIO_FILE" ]]; then
    echo "Error: File not found: $AUDIO_FILE"
    exit 1
fi

if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "Error: GEMINI_API_KEY not set"
    exit 1
fi

# Convert to MP3 (16kHz mono) for Gemini API
CONVERTED_FILE="$OUTPUT_DIR/$(basename "$AUDIO_FILE").mp3"
ffmpeg -y -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a libmp3lame "$CONVERTED_FILE" 2>/dev/null

# Base64 encode
AUDIO_DATA=$(base64 -w0 "$CONVERTED_FILE")

# Call Gemini API
RESPONSE=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"contents\": [{
            \"parts\": [
                {\"text\": \"请将这段音频转录成文字，只输出文字内容\"},
                {\"inlineData\": {
                    \"mimeType\": \"audio/mpeg\",
                    \"data\": \"$AUDIO_DATA\"
                }}
            ]
        }]
    }")

# Extract text from response
TRANSCRIPT=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)

if [[ -z "$TRANSCRIPT" || "$TRANSCRIPT" == "null" ]]; then
    echo "Error: Failed to transcribe audio"
    echo "$RESPONSE"
    exit 1
fi

echo "$TRANSCRIPT"

# Cleanup
rm -f "$CONVERTED_FILE"
