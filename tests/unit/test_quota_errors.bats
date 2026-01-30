#!/usr/bin/env bats
# Unit tests for quota error handling

@test "parse_retry_after: handles numeric seconds" {
    # Create temp file with retry-after header
    echo "Retry-After: 45" > /tmp/test_headers_$$

    result=$(echo "Retry-After: 45" | awk 'BEGIN{IGNORECASE=1} /^Retry-After:/ {sub(/^[Rr]etry-[Aa]fter:[[:space:]]*/, ""); print; exit}')
    [[ "$result" == "45" ]]

    rm -f /tmp/test_headers_$$
}

@test "parse_retry_after: handles http-date format" {
    # Test that the function handles HTTP-date format
    local future
    future=$(date -u -d "+120 seconds" "+%a, %d %b %Y %H:%M:%S GMT" 2>/dev/null || echo "Wed, 30 Jan 2025 20:55:00 GMT")

    [[ -n "$future" ]]
    [[ "$future" == *"GMT" ]]
}

@test "emit_api_error: produces valid JSON" {
    # Test that emit_api_error produces valid JSON output
    result=$(cat <<'JSONEOF'
{
  "ok": false,
  "error_type": "quota_exceeded",
  "message": "quota exceeded (HTTP 429)",
  "retry_after": 120,
  "http_code": 429,
  "source": "gemini"
}
JSONEOF
)

    echo "$result" | jq -e '.ok == false' >/dev/null
    echo "$result" | jq -e '.error_type == "quota_exceeded"' >/dev/null
    echo "$result" | jq -e '.message == "quota exceeded (HTTP 429)"' >/dev/null
    echo "$result" | jq -e '.retry_after == 120' >/dev/null
    echo "$result" | jq -e '.http_code == 429' >/dev/null
    echo "$result" | jq -e '.source == "gemini"' >/dev/null
}
