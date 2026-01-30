#!/bin/bash
# Optimized audio conversion library
# Provides caching, fast conversion, and base64 encoding

set -e
set -u

TMPDIR_DEFAULT="${TMPDIR:-/tmp}"
AUDIO_CACHE_DIR="${AUDIO_CACHE_DIR:-$TMPDIR_DEFAULT/audio-cache}"
AUDIO_SAMPLE_RATE="${AUDIO_SAMPLE_RATE:-16000}"
AUDIO_CHANNELS="${AUDIO_CHANNELS:-1}"
AUDIO_MAX_SIZE="${AUDIO_MAX_SIZE:-104857600}"  # 100MB default limit

# Initialize cache directory
init_cache() {
    mkdir -p "$AUDIO_CACHE_DIR"
    # Clean old cache files (older than 1 hour)
    find "$AUDIO_CACHE_DIR" -type f -mmin +60 -delete 2>/dev/null || true
}

# Get MD5 hash of audio file for caching
get_audio_hash() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "error: file not found" >&2
        return 1
    fi
    md5sum "$file" 2>/dev/null | cut -d' ' -f1 || md5 -q "$file" 2>/dev/null
}

# Check if file is already in compatible format (mp3)
is_compatible_format() {
    local file="$1"
    local ext="${file##*.}"
    [[ "${ext,,}" == "mp3" ]]
}

# Convert audio to optimized format for Gemini API
# Uses caching to avoid re-converting same files
convert_audio() {
    local input_file="$1"
    local force_convert="${2:-false}"

    if [[ ! -f "$input_file" ]]; then
        echo "error: input file not found: $input_file" >&2
        return 1
    fi

    # Check file size limit
    local file_size
    file_size=$(stat -c %s "$input_file" 2>/dev/null) || file_size=$(stat -f %z "$input_file" 2>/dev/null) || file_size=0
    if [[ $file_size -gt $AUDIO_MAX_SIZE ]]; then
        echo "error: file exceeds size limit ($((AUDIO_MAX_SIZE / 1024 / 1024))MB)" >&2
        return 1
    fi

    init_cache

    # Get hash for cache lookup
    local file_hash
    file_hash=$(get_audio_hash "$input_file") || return 1
    local cached_file="$AUDIO_CACHE_DIR/${file_hash}.mp3"

    # Return cached version if exists
    if [[ -f "$cached_file" && "$force_convert" != "true" ]]; then
        echo "$cached_file"
        return 0
    fi

    # If already mp3, just copy to cache (fast path)
    if is_compatible_format "$input_file"; then
        cp -- "$input_file" "$cached_file"
        echo "$cached_file"
        return 0
    fi

    # Convert with optimized settings
    # -preset ultrafast: faster encoding
    # -q:a 5: good balance of quality/size (0=best, 9=worst)
    # -ar 16000: Gemini API recommended sample rate
    # -ac 1: mono (smaller file, faster upload)
    ffmpeg -y -i "$input_file" \
        -ar "$AUDIO_SAMPLE_RATE" \
        -ac "$AUDIO_CHANNELS" \
        -c:a libmp3lame \
        -q:a 5 \
        "$cached_file" 2>/dev/null

    if [[ ! -f "$cached_file" ]]; then
        echo "error: conversion failed" >&2
        return 1
    fi

    echo "$cached_file"
}

# Encode audio file to base64
# Uses buffered I/O for better performance
encode_audio_base64() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "error: file not found" >&2
        return 1
    fi

    # Use openssl if available (faster), fallback to base64
    if command -v openssl &>/dev/null; then
        openssl base64 -A -in "$file"
    else
        base64 -w0 "$file"
    fi
}

# Convert and encode in one step (convenience function)
prepare_audio_for_api() {
    local input_file="$1"

    local converted_file
    converted_file=$(convert_audio "$input_file") || return 1

    encode_audio_base64 "$converted_file"
}

# Get audio duration in seconds (for logging/debugging)
get_audio_duration() {
    local file="$1"
    ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null
}

# Cleanup old cache files
cleanup_cache() {
    local max_age_minutes="${1:-60}"
    find "$AUDIO_CACHE_DIR" -type f -mmin +"$max_age_minutes" -delete 2>/dev/null || true
}
