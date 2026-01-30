#!/bin/bash
# Voice command analyzer - transcribe and understand intent
# Optimized version with better prompts and caching

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
source "$SCRIPT_DIR/lib/convert-audio.sh"
source "$SCRIPT_DIR/lib/gemini-client.sh"
source "$SCRIPT_DIR/lib/prompts.sh"

AUDIO_FILE=""
MODEL=""
CONTEXT=""

usage() {
    echo "Usage: $0 <audio_file> [--model <name>] [--context <text>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --model)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --model requires a value" >&2
                usage
            fi
            MODEL="$2"
            shift 2
            ;;
        --context)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --context requires a value" >&2
                usage
            fi
            CONTEXT="$2"
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

# Validate API key
validate_api_key || exit 1

# Select model for intent analysis
if [[ -z "$MODEL" ]]; then
    MODEL=$(select_model "intent")
fi

# Convert audio (with caching)
CONVERTED_FILE=$(convert_audio "$AUDIO_FILE") || {
    echo "Error: Failed to convert audio" >&2
    exit 1
}

# Encode to base64
AUDIO_DATA=$(encode_audio_base64 "$CONVERTED_FILE")

# Build intent analysis prompt
PROMPT=$(build_intent_prompt "$CONTEXT")

# Build payload with jq
PAYLOAD=$(jq -n \
    --arg prompt "$PROMPT" \
    --arg audio "$AUDIO_DATA" \
    '{
        contents: [{
            parts: [
                {text: $prompt},
                {inlineData: {mimeType: "audio/mpeg", data: $audio}}
            ]
        }]
    }')

# Call API
RESPONSE=$(call_gemini_api "$PAYLOAD" "$MODEL" "intent") || {
    echo "Error: Failed to analyze intent" >&2
    exit 1
}

# Parse and apply corrections to transcribed text
RESULT=$(parse_response "$RESPONSE")

# If result is JSON, extract text and correct it
if echo "$RESULT" | jq -e '.text' &>/dev/null; then
    TEXT=$(echo "$RESULT" | jq -r '.text')
    CORRECTED_TEXT=$(echo "$TEXT" | python3 "$SCRIPT_DIR/lib/corrections.py")
    RESULT=$(echo "$RESULT" | jq --arg text "$CORRECTED_TEXT" '.text = $text')
fi

echo "$RESULT"
