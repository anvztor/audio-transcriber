#!/bin/bash
# Enhanced voice transcriber with semantic error correction
# Uses optimized libraries for caching, retry, and correction

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
source "$SCRIPT_DIR/lib/convert-audio.sh"
source "$SCRIPT_DIR/lib/gemini-client.sh"
source "$SCRIPT_DIR/lib/prompts.sh"

AUDIO_FILE="${1:-}"
MODEL=""
SHOW_ORIGINAL=false

usage() {
    echo "Usage: $0 <audio_file> [--show-original]"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --show-original)
            SHOW_ORIGINAL=true
            shift
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

[[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]] && usage

# Validate API key
validate_api_key || exit 1

# Select model
MODEL=$(select_model "transcribe")

# Step 1: Convert audio (with caching)
CONVERTED_FILE=$(convert_audio "$AUDIO_FILE") || {
    echo "Error: Failed to convert audio" >&2
    exit 1
}

# Step 2: Encode and transcribe
AUDIO_DATA=$(encode_audio_base64 "$CONVERTED_FILE")
PROMPT=$(build_transcription_prompt)

TRANSCRIPT=$(transcribe_audio "$AUDIO_DATA" "$PROMPT" "$MODEL") || {
    echo "Error: Transcription failed" >&2
    exit 1
}

# Step 3: Apply semantic corrections
CORRECTED=$(echo "$TRANSCRIPT" | python3 "$SCRIPT_DIR/lib/corrections.py") || {
    # Fallback to original transcript if correction fails
    CORRECTED="$TRANSCRIPT"
}

# Output result
if [[ "$SHOW_ORIGINAL" == "true" && "$CORRECTED" != "$TRANSCRIPT" ]]; then
    echo "$CORRECTED (corrected from: $TRANSCRIPT)"
else
    echo "$CORRECTED"
fi
