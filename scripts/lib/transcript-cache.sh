#!/bin/bash
# Transcript caching utilities keyed by audio hash

set -e
set -u

TMPDIR_DEFAULT="${TMPDIR:-/tmp}"
TRANSCRIPT_CACHE_DIR="${TRANSCRIPT_CACHE_DIR:-$TMPDIR_DEFAULT/transcript-cache}"
TRANSCRIPT_CACHE_TTL_MINUTES="${TRANSCRIPT_CACHE_TTL_MINUTES:-1440}"

init_transcript_cache() {
    mkdir -p "$TRANSCRIPT_CACHE_DIR"
    # Clean old cache files (default 24h)
    find "$TRANSCRIPT_CACHE_DIR" -type f -mmin +"$TRANSCRIPT_CACHE_TTL_MINUTES" -delete 2>/dev/null || true
}

get_transcript_cache_path() {
    local audio_file="$1"
    local file_hash
    file_hash=$(get_audio_hash "$audio_file") || return 1
    echo "$TRANSCRIPT_CACHE_DIR/${file_hash}.txt"
}

read_transcript_cache() {
    local audio_file="$1"
    init_transcript_cache

    local cache_path
    cache_path=$(get_transcript_cache_path "$audio_file") || return 1

    if [[ -f "$cache_path" ]]; then
        cat "$cache_path"
        return 0
    fi

    return 1
}

write_transcript_cache() {
    local audio_file="$1"
    local transcript="$2"
    init_transcript_cache

    local cache_path
    cache_path=$(get_transcript_cache_path "$audio_file") || return 1

    printf "%s" "$transcript" > "$cache_path"
}
