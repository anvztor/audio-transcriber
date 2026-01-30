#!/usr/bin/env bats
# Unit tests for gemini-client.sh library

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")/../scripts" && pwd)"
    source "$SCRIPT_DIR/lib/gemini-client.sh"

    # Mock API key for testing
    export GEMINI_API_KEY="test-key-12345"
}

@test "validate_api_key: passes with valid key" {
    export GEMINI_API_KEY="valid-key"
    run validate_api_key
    [ "$status" -eq 0 ]
}

@test "validate_api_key: fails without key" {
    unset GEMINI_API_KEY
    run validate_api_key
    [ "$status" -ne 0 ]
}

@test "validate_api_key: fails with empty key" {
    export GEMINI_API_KEY=""
    run validate_api_key
    [ "$status" -ne 0 ]
}

@test "build_api_url: constructs correct URL" {
    local url=$(build_api_url "gemini-2.5-flash")

    [[ "$url" == *"generativelanguage.googleapis.com"* ]]
    [[ "$url" == *"gemini-2.5-flash"* ]]
    [[ "$url" == *"generateContent"* ]]
}

@test "build_api_url: includes API key" {
    local url=$(build_api_url "gemini-2.5-flash")

    [[ "$url" == *"key=test-key-12345"* ]]
}

@test "get_timeout: returns default for transcription" {
    local timeout=$(get_timeout "transcribe")
    [ "$timeout" -eq 30 ]
}

@test "get_timeout: returns longer for intent analysis" {
    local timeout=$(get_timeout "intent")
    [ "$timeout" -eq 45 ]
}

@test "get_retry_delay: implements exponential backoff" {
    local delay1=$(get_retry_delay 1)
    local delay2=$(get_retry_delay 2)
    local delay3=$(get_retry_delay 3)

    [ "$delay1" -eq 1 ]
    [ "$delay2" -eq 2 ]
    [ "$delay3" -eq 4 ]
}

@test "parse_response: extracts text from valid response" {
    local response='{"candidates":[{"content":{"parts":[{"text":"Hello world"}]}}]}'
    local text=$(parse_response "$response")

    [ "$text" = "Hello world" ]
}

@test "parse_response: returns error for invalid response" {
    local response='{"error": "bad request"}'
    run parse_response "$response"
    [ "$status" -ne 0 ]
}

@test "parse_response: handles null text" {
    local response='{"candidates":[{"content":{"parts":[{"text":null}]}}]}'
    run parse_response "$response"
    [ "$status" -ne 0 ]
}
