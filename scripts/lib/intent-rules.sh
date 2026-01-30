#!/bin/bash
# Local intent analysis rules for offline fallback

set -e
set -u

INTENT_TEST_REGEX='(^|[^a-z])(test|self test|self-test|audio test|mic test|microphone test|sound check|check mic)([^a-z]|$)'
INTENT_HELP_REGEX='(^|[^a-z])(help|usage|how do i|what can you do|commands|instruction)([^a-z]|$)'
INTENT_LIST_REGEX='(^|[^a-z])(list|show|display|available|options|all commands)([^a-z]|$)'
INTENT_STATUS_REGEX='(^|[^a-z])(status|state|health|uptime|are you running|system status)([^a-z]|$)'
INTENT_WEATHER_REGEX='(^|[^a-z])(weather|forecast|temperature|rain|snow|humidity)([^a-z]|$)'
INTENT_TIME_REGEX='(^|[^a-z])(time|date|clock|current time|what time|today)([^a-z]|$)'

INTENT_UNSAFE_REGEX='(^|[^a-z])(delete|remove|rm|erase|shutdown|power off|reboot|restart|format|wipe|kill|terminate|drop database|drop table|factory reset|sudo)([^a-z]|$)'

normalize_intent_text() {
    local text="$1"
    echo "$text" | tr '[:upper:]' '[:lower:]'
}

analyze_intent_local() {
    local text="${1:-}"
    local normalized
    local intent="unknown"
    local action="none"
    local safe="true"

    normalized=$(normalize_intent_text "$text")

    if [[ "$normalized" =~ $INTENT_TEST_REGEX ]]; then
        intent="test"
        action="run_test"
    elif [[ "$normalized" =~ $INTENT_HELP_REGEX ]]; then
        intent="help"
        action="show_help"
    elif [[ "$normalized" =~ $INTENT_LIST_REGEX ]]; then
        intent="list"
        action="list_commands"
    elif [[ "$normalized" =~ $INTENT_STATUS_REGEX ]]; then
        intent="status"
        action="show_status"
    elif [[ "$normalized" =~ $INTENT_WEATHER_REGEX ]]; then
        intent="weather"
        action="get_weather"
    elif [[ "$normalized" =~ $INTENT_TIME_REGEX ]]; then
        intent="time"
        action="get_time"
    fi

    if [[ "$normalized" =~ $INTENT_UNSAFE_REGEX ]]; then
        safe="false"
        if [[ "$intent" == "unknown" ]]; then
            intent="unsafe"
            action="review_request"
        fi
    fi

    jq -n \
        --arg text "$text" \
        --arg intent "$intent" \
        --arg action "$action" \
        --argjson safe "$safe" \
        '{
            text: $text,
            intent: $intent,
            action: $action,
            safe: $safe
        }'
}
