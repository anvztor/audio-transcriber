#!/bin/bash
# Transcribe audio and return text for agent to process
# Optimized version with caching

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
source "$SCRIPT_DIR/lib/convert-audio.sh"
source "$SCRIPT_DIR/lib/gemini-client.sh"
source "$SCRIPT_DIR/lib/prompts.sh"
source "$SCRIPT_DIR/lib/transcript-cache.sh"

AUDIO_FILE="${1:-}"

[[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]] && exit 1

emit_api_error() {
    local error_type="$1"
    local message="$2"
    local retry_after="${3:-}"
    local http_code="${4:-}"

    jq -n \
        --arg type "$error_type" \
        --arg message "$message" \
        --arg retry_after "${retry_after:-}" \
        --arg http_code "${http_code:-}" \
        '{
            ok: false,
            error_type: $type,
            message: $message,
            retry_after: (if $retry_after == "" then null else ($retry_after | tonumber? // $retry_after) end),
            http_code: (if $http_code == "" then null else ($http_code | tonumber? // $http_code) end),
            source: "gemini"
        }'
}

# Validate API key
if ! validate_api_key; then
    emit_api_error "missing_api_key" "GEMINI_API_KEY not set"
    exit 0
fi

# Check transcript cache before calling API
if cached_transcript=$(read_transcript_cache "$AUDIO_FILE" 2>/dev/null); then
    printf "%s" "$cached_transcript"
    exit 0
fi

# Convert audio (with caching)
CONVERTED_FILE=$(convert_audio "$AUDIO_FILE") || exit 1

# Transcribe with simple prompt (faster)
AUDIO_DATA=$(encode_audio_base64 "$CONVERTED_FILE")
PROMPT=$(build_simple_prompt)
MODEL=$(select_model "simple")

if transcript=$(transcribe_audio "$AUDIO_DATA" "$PROMPT" "$MODEL" 2>/dev/null); then
    write_transcript_cache "$AUDIO_FILE" "$transcript" || true
    printf "%s" "$transcript"
    exit 0
fi

emit_api_error \
    "${GEMINI_LAST_ERROR_TYPE:-api_error}" \
    "${GEMINI_LAST_ERROR_MESSAGE:-API request failed}" \
    "${GEMINI_LAST_RETRY_AFTER:-}" \
    "${GEMINI_LAST_HTTP_CODE:-}"
