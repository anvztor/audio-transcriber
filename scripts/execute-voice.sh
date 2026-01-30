#!/bin/bash
# Complete voice command handler - transcribe, understand, and execute

set -e

AUDIO_FILE="$1"
MODEL="gemini-2.5-flash"

if [[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]]; then
    echo "Usage: $0 <audio_file>"
    exit 1
fi

if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "Error: GEMINI_API_KEY not set"
    exit 1
fi

# Convert to MP3
ffmpeg -y -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a libmp3lame /tmp/voice_temp.mp3 2>/dev/null

# Transcribe and get intent
AUDIO_DATA=$(base64 -w0 /tmp/voice_temp.mp3)

RESPONSE=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"contents\": [{
            \"parts\": [
                {\"text\": \"分析用户语音指令，提取需求。只输出JSON：{\\\"text\\\":\\\"转录的文字\\\",\\\"intent\\\":\\\"用户想要什么\\\",\\\"action\\\":\\\"下一步应该执行什么命令或操作\\\"}\"},
                {\"inlineData\": {\"mimeType\": \"audio/mpeg\", \"data\": \"$AUDIO_DATA\"}}
            ]
        }]
    }")

rm -f /tmp/voice_temp.mp3

# Extract and execute
INTENT=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)

echo "【语音识别结果】"
echo "$INTENT"
echo ""
echo "【执行中...】"

# Try to execute the action
ACTION=$(echo "$INTENT" | jq -r '.action' 2>/dev/null)
if [[ -n "$ACTION" && "$ACTION" != "null" && ${#ACTION} -gt 5 ]]; then
    echo "执行命令: $ACTION"
    eval "$ACTION" 2>&1 || echo "命令执行失败或需要人工处理"
else
    echo "需要我帮你做什么？直接告诉我吧。"
fi
