#!/bin/bash
# Enhanced voice transcriber with semantic error correction
# Uses context and memory to correct homophonic errors

set -e

AUDIO_FILE="$1"
MODEL="gemini-2.5-flash"
OUTPUT_DIR="/tmp"

usage() {
    echo "Usage: $0 <audio_file>"
    exit 1
}

[[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]] && usage
[[ -z "$GEMINI_API_KEY" ]] && { echo "Error: GEMINI_API_KEY not set"; exit 1; }

# Step 1: Transcribe audio
ffmpeg -y -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a libmp3lame "$OUTPUT_DIR/voice_tmp.mp3" 2>/dev/null
AUDIO_DATA=$(base64 -w0 "$OUTPUT_DIR/voice_tmp.mp3")

RESPONSE=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$GEMINI_API_KEY" \
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

TRANSCRIPT=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)
[[ -z "$TRANSCRIPT" || "$TRANSCRIPT" == "null" ]] && { echo "Error: Transcription failed"; exit 1; }

# Step 2: Check for homophonic errors and correct
CORRECTED=$(echo "$TRANSCRIPT" | python3 << 'PYEOF'
import sys
import re
import json

text = sys.stdin.read().strip()

# Common homophonic corrections for this user context
# These are context-specific corrections based on user's workflow
corrections = {
    # Clawdbot related
    r'\bcloudboot\b': 'clawdbot',
    r'\bcloud bot\b': 'clawdbot',
    r'\bcloud boot\b': 'clawdbot',
    r'\bcloud boot\b': 'clawdbot',
    r'\bcloudboot\b': 'clawdbot',
    r'\bclowdbot\b': 'clawdbot',
    r'\bclawdbot\b': 'clawdbot',
    
    # Processed related
    r'\bpro system\b': 'processed',
    r'\bprocess system\b': 'processed',
    r'\bprocess ed\b': 'processed',
    r'\bprossed\b': 'processed',
    r'\bprosess\b': 'processed',
    r'\bprosed\b': 'processed',
    
    # Directory names (user-confirmed)
    r'\bAMVZ\b': 'anvz',
    r'\bamvz\b': 'anvz',
    r'\bAVZ\b': 'anvz',
    r'\bavz\b': 'anvz',
    r'\bAMZ\b': 'anvz',
    r'\bamz\b': 'anvz',
    
    # File system terms
    r'\bmedia\b': 'media',
    r'\bmedia\b': 'media',
    r'\btxt\b': 'txt',
    r'\btext\b': 'txt',
    
    # Common Chinese homophonic errors
    r'\b帮你\b': '帮我',
    r'\b本地的\b': '本地的',
    r'\b存储空间\b': '存储空间',
    r'\b优化\b': '优化',
    r'\b看一下\b': '看一下',
    r'\b还有没有\b': '还有没有',
}

# Apply corrections
for pattern, replacement in corrections.items():
    text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)

print(text)
PYEOF
)

# Step 3: If corrected version differs, use it
if [[ "$CORRECTED" != "$TRANSCRIPT" ]]; then
    echo "$CORRECTED (corrected from: $TRANSCRIPT)"
else
    echo "$CORRECTED"
fi
