#!/bin/bash
# Audio transcription script using Gemini API
# Optimized version with caching and retry logic

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
source "$SCRIPT_DIR/lib/convert-audio.sh"
source "$SCRIPT_DIR/lib/gemini-client.sh"
source "$SCRIPT_DIR/lib/prompts.sh"

AUDIO_FILE=""
MODEL=""
TMPDIR_DEFAULT="${TMPDIR:-/tmp}"
OUTPUT_DIR="${OUTPUT_DIR:-$TMPDIR_DEFAULT}"
USE_SIMPLE_PROMPT=false

usage() {
    echo "Usage: $0 <audio_file> [--model <name>] [--out <dir>] [--simple]"
    echo "Example: $0 audio.ogg --model gemini-2.0-flash"
    exit 1
}

# Parse arguments
validate_path_arg() {
    local path="$1"
    if [[ -z "$path" ]]; then
        echo "Error: path is empty" >&2
        return 1
    fi
    if [[ "$path" == -* ]]; then
        echo "Error: path must not start with '-': $path" >&2
        return 1
    fi
    if [[ "$path" == *$'\n'* || "$path" == *$'\r'* ]]; then
        echo "Error: path contains newline characters" >&2
        return 1
    fi
}

# Parse arguments
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
        --out)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --out requires a value" >&2
                usage
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --simple)
            USE_SIMPLE_PROMPT=true
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

if [[ -z "$AUDIO_FILE" ]]; then
    usage
fi

validate_path_arg "$AUDIO_FILE"
validate_path_arg "$OUTPUT_DIR"

if [[ ! -f "$AUDIO_FILE" ]]; then
    echo "Error: File not found: $AUDIO_FILE" >&2
    exit 1
fi

# Validate API key
validate_api_key || exit 1

# Select model if not specified
if [[ -z "$MODEL" ]]; then
    MODEL=$(select_model "transcribe")
fi

# Convert audio (with caching)
CONVERTED_FILE=$(convert_audio "$AUDIO_FILE") || {
    echo "Error: Failed to convert audio" >&2
    exit 1
}

# Encode to base64
AUDIO_DATA=$(encode_audio_base64 "$CONVERTED_FILE") || {
    echo "Error: Failed to encode audio" >&2
    exit 1
}

# Build prompt
if [[ "$USE_SIMPLE_PROMPT" == "true" ]]; then
    PROMPT=$(build_simple_prompt)
else
    PROMPT=$(build_transcription_prompt)
fi

# Call API with retry logic
TRANSCRIPT=$(transcribe_audio "$AUDIO_DATA" "$PROMPT" "$MODEL") || {
    echo "Error: Failed to transcribe audio" >&2
    exit 1
}

echo "$TRANSCRIPT"
