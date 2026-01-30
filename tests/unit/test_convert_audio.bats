#!/usr/bin/env bats
# Unit tests for convert-audio.sh library

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")/../scripts" && pwd)"
    source "$SCRIPT_DIR/lib/convert-audio.sh"

    # Create temp directory for test files
    export TEST_TMP="$BATS_TMPDIR/audio_test_$$"
    mkdir -p "$TEST_TMP"

    # Create a minimal valid audio file for testing (1 second of silence)
    ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 0.5 -q:a 9 "$TEST_TMP/test.mp3" -y 2>/dev/null
}

teardown() {
    rm -rf "$TEST_TMP"
    rm -rf /tmp/audio-cache 2>/dev/null || true
}

@test "convert_audio: converts ogg to mp3" {
    # Create test ogg file
    ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 0.5 "$TEST_TMP/input.ogg" -y 2>/dev/null

    result=$(convert_audio "$TEST_TMP/input.ogg")

    [ -f "$result" ]
    [[ "$result" == *.mp3 ]]
}

@test "convert_audio: uses cache for same file" {
    local first_result=$(convert_audio "$TEST_TMP/test.mp3")
    local first_mtime=$(stat -c %Y "$first_result" 2>/dev/null || stat -f %m "$first_result")

    sleep 1

    local second_result=$(convert_audio "$TEST_TMP/test.mp3")
    local second_mtime=$(stat -c %Y "$second_result" 2>/dev/null || stat -f %m "$second_result")

    # Same file should be returned (mtime unchanged)
    [ "$first_result" = "$second_result" ]
    [ "$first_mtime" = "$second_mtime" ]
}

@test "convert_audio: skips conversion for compatible mp3" {
    # Already 16kHz mono mp3 should skip conversion
    local start_time=$(date +%s%N)
    convert_audio "$TEST_TMP/test.mp3" >/dev/null
    local end_time=$(date +%s%N)

    # Should be fast (< 500ms) since no conversion needed
    local duration=$(( (end_time - start_time) / 1000000 ))
    [ "$duration" -lt 500 ]
}

@test "convert_audio: handles missing file" {
    run convert_audio "/nonexistent/file.mp3"
    [ "$status" -ne 0 ]
}

@test "encode_audio_base64: returns valid base64" {
    local result=$(encode_audio_base64 "$TEST_TMP/test.mp3")

    # Should be non-empty base64 string
    [ -n "$result" ]
    # Should decode successfully
    echo "$result" | base64 -d >/dev/null 2>&1
    [ $? -eq 0 ]
}

@test "get_audio_hash: returns consistent hash" {
    local hash1=$(get_audio_hash "$TEST_TMP/test.mp3")
    local hash2=$(get_audio_hash "$TEST_TMP/test.mp3")

    [ "$hash1" = "$hash2" ]
    [ ${#hash1} -gt 10 ]
}

@test "get_audio_hash: different files have different hashes" {
    ffmpeg -f lavfi -i anullsrc=r=8000:cl=mono -t 0.3 "$TEST_TMP/other.mp3" -y 2>/dev/null

    local hash1=$(get_audio_hash "$TEST_TMP/test.mp3")
    local hash2=$(get_audio_hash "$TEST_TMP/other.mp3")

    [ "$hash1" != "$hash2" ]
}

@test "is_compatible_format: recognizes mp3" {
    run is_compatible_format "$TEST_TMP/test.mp3"
    [ "$status" -eq 0 ]
}

@test "is_compatible_format: rejects wav" {
    ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 0.5 "$TEST_TMP/test.wav" -y 2>/dev/null
    run is_compatible_format "$TEST_TMP/test.wav"
    [ "$status" -ne 0 ]
}
