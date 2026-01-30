#!/bin/bash
# Voice command executor - transcribe, understand intent, and execute task

set -e

AUDIO_FILE=""
MODEL="gemini-2.5-flash"
OUTPUT_DIR="/tmp"

usage() {
    echo "Usage: $0 <audio_file> [--model <name>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            MODEL="$2"
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

if [[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]]; then
    usage
fi

if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "Error: GEMINI_API_KEY not set"
    exit 1
fi

# Convert to MP3
CONVERTED_FILE="$OUTPUT_DIR/$(basename "$AUDIO_FILE").mp3"
ffmpeg -y -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a libmp3lame "$CONVERTED_FILE" 2>/dev/null

# Transcribe
AUDIO_DATA=$(base64 -w0 "$CONVERTED_FILE")

RESPONSE=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"contents\": [{
            \"parts\": [
                {\"text\": \"请将这段音频转录成文字，并分析用户的意图和需求。只输出以下格式：\\n【转录】<用户说的话>\\n【意图】<一句话说明用户想要什么>\\n【任务类型】<read/exec/memory/search/help/other>\"},
                {\"inlineData\": {\"mimeType\": \"audio/mpeg\", \"data\": \"$AUDIO_DATA\"}}
            ]
        }]
    }")

TRANSCRIPT=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)

if [[ -z "$TRANSCRIPT" || "$TRANSCRIPT" == "null" ]]; then
    echo "Error: Failed to transcribe"
    exit 1
fi

echo "$TRANSCRIPT"
rm -f "$CONVERTED_FILE"
