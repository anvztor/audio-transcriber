#!/bin/bash
# Transcribe audio and return text for agent to process
# Optimized version with caching

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSCRIBER_MODE="${TRANSCRIBER_MODE:-api}"

# Source library functions
source "$SCRIPT_DIR/lib/convert-audio.sh"
source "$SCRIPT_DIR/lib/prompts.sh"
source "$SCRIPT_DIR/lib/transcript-cache.sh"

if [[ "$TRANSCRIBER_MODE" == "local" ]]; then
    source "$SCRIPT_DIR/lib/whisper-client.sh"
else
    source "$SCRIPT_DIR/lib/gemini-client.sh"
fi

AUDIO_FILE="${1:-}"

[[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]] && exit 1

emit_transcriber_error() {
    local source="$1"
    local error_type="$2"
    local message="$3"
    local retry_after="${4:-}"
    local http_code="${5:-}"

    jq -n \
        --arg source "$source" \
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
            source: $source
        }'
}

case "$TRANSCRIBER_MODE" in
    api|local) ;;
    *)
        emit_transcriber_error "config" "invalid_mode" "TRANSCRIBER_MODE must be 'api' or 'local'"
        exit 0
        ;;
esac

if [[ "$TRANSCRIBER_MODE" == "api" ]]; then
    if ! validate_api_key; then
        emit_transcriber_error "gemini" "missing_api_key" "GEMINI_API_KEY not set"
        exit 0
    fi
else
    if ! check_whisper_installed; then
        if ! install_whisper_if_needed; then
            emit_transcriber_error "whisper" "missing_dependency" "openai-whisper not installed"
            exit 0
        fi
    fi
fi

# Check transcript cache before calling API
if cached_transcript=$(read_transcript_cache "$AUDIO_FILE" 2>/dev/null); then
    printf "%s" "$cached_transcript"
    exit 0
fi

# Convert audio (with caching)
CONVERTED_FILE=$(convert_audio "$AUDIO_FILE") || exit 1

if [[ "$TRANSCRIBER_MODE" == "local" ]]; then
    if transcript=$(transcribe_audio_whisper "$CONVERTED_FILE" "${WHISPER_MODEL:-}" 2>/dev/null); then
        write_transcript_cache "$AUDIO_FILE" "$transcript" || true
        printf "%s" "$transcript"
        exit 0
    fi

    emit_transcriber_error "whisper" "transcription_error" "Whisper transcription failed"
    exit 0
fi

# Transcribe with simple prompt (faster)
AUDIO_DATA=$(encode_audio_base64 "$CONVERTED_FILE")
PROMPT=$(build_simple_prompt)
MODEL=$(select_model "simple")

if transcript=$(transcribe_audio "$AUDIO_DATA" "$PROMPT" "$MODEL" 2>/dev/null); then
    write_transcript_cache "$AUDIO_FILE" "$transcript" || true
    printf "%s" "$transcript"
    exit 0
fi

emit_transcriber_error \
    "gemini" \
    "${GEMINI_LAST_ERROR_TYPE:-api_error}" \
    "${GEMINI_LAST_ERROR_MESSAGE:-API request failed}" \
    "${GEMINI_LAST_RETRY_AFTER:-}" \
    "${GEMINI_LAST_HTTP_CODE:-}"
