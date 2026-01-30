#!/bin/bash
# Voice command analyzer - transcribe and understand intent
# Optimized version with better prompts and caching

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSCRIBER_MODE="${TRANSCRIBER_MODE:-api}"

# Source library functions
source "$SCRIPT_DIR/lib/convert-audio.sh"
source "$SCRIPT_DIR/lib/gemini-client.sh"
source "$SCRIPT_DIR/lib/intent-rules.sh"
source "$SCRIPT_DIR/lib/prompts.sh"
source "$SCRIPT_DIR/lib/whisper-client.sh"

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

case "$TRANSCRIBER_MODE" in
    api|local) ;;
    *)
        echo "Error: TRANSCRIBER_MODE must be 'api' or 'local'" >&2
        exit 1
        ;;
esac

if [[ "$TRANSCRIBER_MODE" == "api" ]]; then
    # Validate API key
    validate_api_key || exit 1
else
    if ! check_whisper_installed; then
        if ! install_whisper_if_needed; then
            echo "Error: openai-whisper not installed" >&2
            exit 1
        fi
    fi
fi

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

# Local mode: transcribe with Whisper and analyze intent rules
if [[ "$TRANSCRIBER_MODE" == "local" ]]; then
    TRANSCRIPT=$(transcribe_audio_whisper "$CONVERTED_FILE" "${WHISPER_MODEL:-}" 2>/dev/null) || {
        echo "Error: Failed to transcribe audio locally" >&2
        exit 1
    }
    RESULT=$(analyze_intent_local "$TRANSCRIPT")
else
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
        if [[ "${GEMINI_LAST_ERROR_TYPE:-}" == "quota_exceeded" ]]; then
            if ! check_whisper_installed; then
                if ! install_whisper_if_needed; then
                    echo "Error: openai-whisper not installed for quota fallback" >&2
                    exit 1
                fi
            fi
            TRANSCRIPT=$(transcribe_audio_whisper "$CONVERTED_FILE" "${WHISPER_MODEL:-}" 2>/dev/null) || {
                echo "Error: Failed to transcribe audio locally after quota exceeded" >&2
                exit 1
            }
            RESULT=$(analyze_intent_local "$TRANSCRIPT")
        else
            echo "Error: Failed to analyze intent" >&2
            exit 1
        fi
    }

# Parse and apply corrections to transcribed text
    if [[ -z "${RESULT:-}" ]]; then
        RESULT=$(parse_response "$RESPONSE")
    fi
fi

# If result is JSON, extract text and correct it
if echo "$RESULT" | jq -e '.text' &>/dev/null; then
    TEXT=$(echo "$RESULT" | jq -r '.text')
    CORRECTED_TEXT=$(echo "$TEXT" | python3 "$SCRIPT_DIR/lib/corrections.py")
    RESULT=$(echo "$RESULT" | jq --arg text "$CORRECTED_TEXT" '.text = $text')
fi

echo "$RESULT"
