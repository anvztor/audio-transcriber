#!/bin/bash
# Local intent analysis rules for offline fallback

set -e
set -u

INTENT_TEST_REGEX='(^|[^a-zA-Z0-9])((test|self test|self-test|audio test|mic test|microphone test|sound check|check mic|测试|测试语音|麦克风测试)([^a-zA-Z0-9]|$)|测试$)'
INTENT_HELP_REGEX='(^|[^a-zA-Z0-9])((help|usage|how do i|what can you do|commands|instruction|帮助|指令|怎么用)([^a-zA-Z0-9]|$)|帮助$)'
INTENT_LIST_REGEX='(^|[^a-zA-Z0-9])((list|show|display|available|options|all commands|列出|列表|可用命令)([^a-zA-Z0-9]|$)|列出$)'
INTENT_STATUS_REGEX='(^|[^a-zA-Z0-9])((status|state|health|uptime|are you running|system status|状态|系统状态)([^a-zA-Z0-9]|$)|状态$)'
INTENT_WEATHER_REGEX='(^|[^a-zA-Z0-9])((weather|forecast|temperature|rain|snow|humidity|天气|天气预报)([^a-zA-Z0-9]|$)|天气$)'
INTENT_TIME_REGEX='(^|[^a-zA-Z0-9])((time|date|clock|current time|what time|today|时间|现在几点)([^a-zA-Z0-9]|$)|时间$)'

INTENT_UNSAFE_REGEX='(^|[^a-z])(delete|remove|rm|erase|shutdown|power off|reboot|restart|format|wipe|kill|terminate|drop database|drop table|factory reset|sudo)([^a-z]|$)'

# Chinese patterns - use substring matching (simpler, more reliable for Chinese)
# Include both Simplified (简体) and Traditional (繁體) characters
CHINESE_TEST_PATTERNS=("测试" "測試" "麦克风测试" "麥克風測試" "语音测试" "語音測試")
CHINESE_HELP_PATTERNS=("帮助" "幫助" "指令" "怎么用" "怎麼用" "使用方法")
CHINESE_LIST_PATTERNS=("列表" "列表" "列出" "可用命令" "所有命令")
CHINESE_STATUS_PATTERNS=("状态" "狀態" "系统状态" "系統狀態")
CHINESE_WEATHER_PATTERNS=("天气" "天氣" "天气预报" "天氣預報")
CHINESE_TIME_PATTERNS=("时间" "時間" "现在几点" "現在幾點" "几点" "幾點")

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

    # Check Chinese patterns first (substring match)
    for pattern in "${CHINESE_TEST_PATTERNS[@]}"; do
        if [[ "$normalized" == *"$pattern"* ]]; then
            intent="test"
            action="run_test"
            break
        fi
    done

    if [[ "$intent" == "unknown" ]]; then
        for pattern in "${CHINESE_HELP_PATTERNS[@]}"; do
            if [[ "$normalized" == *"$pattern"* ]]; then
                intent="help"
                action="show_help"
                break
            fi
        done
    fi

    if [[ "$intent" == "unknown" ]]; then
        for pattern in "${CHINESE_LIST_PATTERNS[@]}"; do
            if [[ "$normalized" == *"$pattern"* ]]; then
                intent="list"
                action="list_commands"
                break
            fi
        done
    fi

    if [[ "$intent" == "unknown" ]]; then
        for pattern in "${CHINESE_STATUS_PATTERNS[@]}"; do
            if [[ "$normalized" == *"$pattern"* ]]; then
                intent="status"
                action="show_status"
                break
            fi
        done
    fi

    if [[ "$intent" == "unknown" ]]; then
        for pattern in "${CHINESE_WEATHER_PATTERNS[@]}"; do
            if [[ "$normalized" == *"$pattern"* ]]; then
                intent="weather"
                action="get_weather"
                break
            fi
        done
    fi

    if [[ "$intent" == "unknown" ]]; then
        for pattern in "${CHINESE_TIME_PATTERNS[@]}"; do
            if [[ "$normalized" == *"$pattern"* ]]; then
                intent="time"
                action="get_time"
                break
            fi
        done
    fi

    # Fall back to regex patterns for English
    if [[ "$intent" == "unknown" ]]; then
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
