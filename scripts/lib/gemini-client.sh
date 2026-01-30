#!/bin/bash
# Gemini API client library with retry logic and error handling

set -e
set -u

GEMINI_API_BASE="${GEMINI_API_BASE:-https://generativelanguage.googleapis.com/v1beta}"
GEMINI_MAX_RETRIES="${GEMINI_MAX_RETRIES:-3}"
GEMINI_DEFAULT_MODEL="${GEMINI_DEFAULT_MODEL:-gemini-2.5-flash}"

# Last error details for callers that want structured handling
GEMINI_LAST_ERROR_TYPE=""
GEMINI_LAST_ERROR_MESSAGE=""
GEMINI_LAST_RETRY_AFTER=""
GEMINI_LAST_HTTP_CODE=""

# Validate API key is set
validate_api_key() {
    if [[ -z "${GEMINI_API_KEY:-}" ]]; then
        echo "error: GEMINI_API_KEY not set" >&2
        return 1
    fi
    return 0
}

# Build API URL for model (without key for security)
build_api_url() {
    local model="${1:-$GEMINI_DEFAULT_MODEL}"
    echo "${GEMINI_API_BASE}/models/${model}:generateContent"
}

# Get timeout in seconds based on operation type
get_timeout() {
    local operation="${1:-transcribe}"
    case "$operation" in
        transcribe) echo 30 ;;
        intent) echo 45 ;;
        execute) echo 60 ;;
        *) echo 30 ;;
    esac
}

# Calculate retry delay with exponential backoff
get_retry_delay() {
    local attempt="$1"
    echo $((1 << (attempt - 1)))  # 1, 2, 4, 8...
}

# Reset last error state
reset_last_error() {
    GEMINI_LAST_ERROR_TYPE=""
    GEMINI_LAST_ERROR_MESSAGE=""
    GEMINI_LAST_RETRY_AFTER=""
    GEMINI_LAST_HTTP_CODE=""
}

# Record last error details
set_last_error() {
    local type="$1"
    local message="$2"
    local retry_after="${3:-}"
    local http_code="${4:-}"
    GEMINI_LAST_ERROR_TYPE="$type"
    GEMINI_LAST_ERROR_MESSAGE="$message"
    GEMINI_LAST_RETRY_AFTER="$retry_after"
    GEMINI_LAST_HTTP_CODE="$http_code"
}

# Parse Retry-After header value (seconds or HTTP date)
parse_retry_after() {
    local headers_file="$1"
    local header_value
    header_value=$(awk 'BEGIN{IGNORECASE=1} /^Retry-After:/ {sub(/^[Rr]etry-[Aa]fter:[[:space:]]*/, ""); print; exit}' "$headers_file" 2>/dev/null)

    if [[ -z "$header_value" ]]; then
        return 1
    fi

    if [[ "$header_value" =~ ^[0-9]+$ ]]; then
        echo "$header_value"
        return 0
    fi

    local target_epoch
    target_epoch=$(date -d "$header_value" +%s 2>/dev/null) || return 1
    local now_epoch
    now_epoch=$(date +%s 2>/dev/null) || return 1

    if [[ "$target_epoch" -le "$now_epoch" ]]; then
        echo 0
        return 0
    fi

    echo $((target_epoch - now_epoch))
}

# Parse response and extract text
parse_response() {
    local response="$1"

    # Check for error in response
    if echo "$response" | jq -e '.error' &>/dev/null; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // .error // "unknown error"')
        set_last_error "api_error" "$error_msg" "" ""
        echo "error: API returned error: $error_msg" >&2
        return 1
    fi

    # Extract text from candidates
    local text
    text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)

    if [[ -z "$text" || "$text" == "null" ]]; then
        set_last_error "invalid_response" "no text in response" "" ""
        echo "error: no text in response" >&2
        return 1
    fi

    echo "$text"
}

# Make API call with retry logic
call_gemini_api() {
    local payload="$1"
    local model="${2:-$GEMINI_DEFAULT_MODEL}"
    local operation="${3:-transcribe}"

    reset_last_error
    validate_api_key || return 1

    local url
    url=$(build_api_url "$model")

    local timeout
    timeout=$(get_timeout "$operation")

    local attempt=1
    local response
    local headers_file
    headers_file=$(mktemp)
    trap 'rm -f "$headers_file"' RETURN

    while [[ $attempt -le $GEMINI_MAX_RETRIES ]]; do
        local raw
        local curl_status=0
        # Use header for API key instead of URL parameter (more secure)
        raw=$(curl -s -X POST "${url}?key=${GEMINI_API_KEY}" \
            -H "Content-Type: application/json" \
            --max-time "$timeout" \
            -D "$headers_file" \
            -w "\n%{http_code}" \
            -d "$payload" 2>/dev/null) || curl_status=$?

        if [[ $curl_status -ne 0 || -z "$raw" ]]; then
            set_last_error "network_error" "network error while calling Gemini API" "" ""
            if [[ $attempt -lt $GEMINI_MAX_RETRIES ]]; then
                local delay
                delay=$(get_retry_delay "$attempt")
                sleep "$delay"
                ((attempt++))
                continue
            fi
            return 1
        fi

        local http_code
        http_code="${raw##*$'\n'}"
        response="${raw%$'\n'*}"

        if [[ "$http_code" == "429" ]]; then
            local retry_after
            retry_after=$(parse_retry_after "$headers_file" 2>/dev/null || true)
            set_last_error "quota_exceeded" "quota exceeded (HTTP 429)" "$retry_after" "$http_code"

            if [[ $attempt -lt $GEMINI_MAX_RETRIES ]]; then
                local delay
                delay=$(get_retry_delay "$attempt")
                if [[ -n "${retry_after:-}" && "$retry_after" -gt "$delay" ]]; then
                    delay="$retry_after"
                fi
                sleep "$delay"
                ((attempt++))
                continue
            fi

            echo "error: quota exceeded (HTTP 429)" >&2
            if [[ -n "${retry_after:-}" ]]; then
                echo "error: retry after ${retry_after}s" >&2
            fi
            echo "$response"
            return 1
        fi

        if [[ "$http_code" -ge 400 ]]; then
            local error_msg="HTTP $http_code"
            if echo "$response" | jq -e '.error' &>/dev/null; then
                error_msg=$(echo "$response" | jq -r '.error.message // .error // "unknown error"')
            fi
            set_last_error "api_error" "$error_msg" "" "$http_code"

            if [[ $attempt -lt $GEMINI_MAX_RETRIES ]]; then
                local delay
                delay=$(get_retry_delay "$attempt")
                sleep "$delay"
                ((attempt++))
                continue
            fi

            echo "$response"
            return 1
        fi

        # Check if response is valid (not an error)
        if ! echo "$response" | jq -e '.error' &>/dev/null; then
            echo "$response"
            return 0
        fi

        # Retry on API error responses
        set_last_error "api_error" "API error response" "" "$http_code"
        if [[ $attempt -lt $GEMINI_MAX_RETRIES ]]; then
            local delay
            delay=$(get_retry_delay "$attempt")
            sleep "$delay"
            ((attempt++))
            continue
        fi

        echo "$response"
        return 1
    done

    # Return last response even if failed (for error inspection)
    echo "$response"
    return 1
}

# High-level transcription function
transcribe_audio() {
    local audio_base64="$1"
    local prompt="${2:-请将这段音频转录成文字，只输出文字内容}"
    local model="${3:-$GEMINI_DEFAULT_MODEL}"

    local payload
    payload=$(jq -n \
        --arg prompt "$prompt" \
        --arg audio "$audio_base64" \
        '{
            contents: [{
                parts: [
                    {text: $prompt},
                    {inlineData: {mimeType: "audio/mpeg", data: $audio}}
                ]
            }]
        }')

    local response
    response=$(call_gemini_api "$payload" "$model" "transcribe") || return 1

    parse_response "$response"
}

# High-level intent analysis function
analyze_intent() {
    local audio_base64="$1"
    local context="${2:-}"
    local model="${3:-$GEMINI_DEFAULT_MODEL}"

    local prompt="请分析用户语音指令，提取需求。"
    if [[ -n "$context" ]]; then
        prompt="$prompt 上下文: $context"
    fi
    prompt="$prompt 只输出JSON格式：{\"text\":\"转录的文字\",\"intent\":\"用户想要什么\",\"action\":\"下一步应该执行什么\"}"

    local payload
    payload=$(jq -n \
        --arg prompt "$prompt" \
        --arg audio "$audio_base64" \
        '{
            contents: [{
                parts: [
                    {text: $prompt},
                    {inlineData: {mimeType: "audio/mpeg", data: $audio}}
                ]
            }]
        }')

    local response
    response=$(call_gemini_api "$payload" "$model" "intent") || return 1

    parse_response "$response"
}
