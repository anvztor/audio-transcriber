#!/bin/bash
# Complete voice command handler - transcribe, understand, and execute
# Optimized version with safety checks

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
source "$SCRIPT_DIR/lib/convert-audio.sh"
source "$SCRIPT_DIR/lib/gemini-client.sh"
source "$SCRIPT_DIR/lib/prompts.sh"
source "$SCRIPT_DIR/lib/intent-rules.sh"
source "$SCRIPT_DIR/lib/whisper-client.sh"

TRANSCRIBER_MODE="${TRANSCRIBER_MODE:-api}"

AUDIO_FILE="${1:-}"
MODEL=""
DRY_RUN=false

usage() {
    echo "Usage: $0 <audio_file> [--dry-run]"
    echo "  --dry-run  Show command but don't execute"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            AUDIO_FILE="$1"
            shift
            ;;
    esac
done

validate_audio_path() {
    local path="$1"
    if [[ -z "$path" ]]; then
        echo "Error: audio file path is empty" >&2
        return 1
    fi
    if [[ "$path" == -* ]]; then
        echo "Error: audio file path must not start with '-': $path" >&2
        return 1
    fi
    if [[ "$path" == *$'\n'* || "$path" == *$'\r'* ]]; then
        echo "Error: audio file path contains newline characters" >&2
        return 1
    fi
}

if [[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]]; then
    usage
fi
validate_audio_path "$AUDIO_FILE"

# Check mode
case "$TRANSCRIBER_MODE" in
    api|local) ;;
    *)
        echo "Error: TRANSCRIBER_MODE must be 'api' or 'local'" >&2
        exit 1
        ;;
esac

# Convert audio
CONVERTED_FILE=$(convert_audio "$AUDIO_FILE") || {
    echo "Error: Failed to convert audio" >&2
    exit 1
}

# Local mode: transcribe and use local intent analysis
if [[ "$TRANSCRIBER_MODE" == "local" ]]; then
    if ! check_whisper_installed; then
        if ! install_whisper_if_needed; then
            echo "Error: openai-whisper not installed" >&2
            exit 1
        fi
    fi

    TRANSCRIPT=$(transcribe_audio_whisper "$CONVERTED_FILE" "${WHISPER_MODEL:-}" 2>/dev/null) || {
        echo "Error: Failed to transcribe audio locally" >&2
        exit 1
    }

    INTENT=$(analyze_intent_local "$TRANSCRIPT")
else
    # API mode
    validate_api_key || exit 1
    MODEL=$(select_model "execute")

    AUDIO_DATA=$(encode_audio_base64 "$CONVERTED_FILE")
    PROMPT=$(build_execution_prompt)

    PAYLOAD=$(jq -n \
        --arg prompt "$PROMPT" \
        --arg audio "$AUDIO_DATA" \
        '{
            contents: [{
                parts: [
                    {text: $prompt},
                    {inlineData: {mimeType: "audio/mpeg", data: $audio}}
                ]
            }]
        }')

    RESPONSE=$(call_gemini_api "$PAYLOAD" "$MODEL" "execute") || {
        echo "Error: Failed to analyze command" >&2
        exit 1
    }

    INTENT=$(parse_response "$RESPONSE")
fi

echo "【语音识别结果】"
echo "$INTENT"
echo ""

# Extract action from JSON
ACTION=$(echo "$INTENT" | jq -r '.action // empty' 2>/dev/null)
SAFE=$(echo "$INTENT" | jq -r '.safe // true' 2>/dev/null)

if [[ -z "$ACTION" || "$ACTION" == "null" || ${#ACTION} -lt 5 ]]; then
    echo "需要我帮你做什么？直接告诉我吧。"
    exit 0
fi

# Safety check
if [[ "$SAFE" == "false" ]]; then
    echo "⚠️  检测到可能不安全的操作，跳过执行: $ACTION"
    exit 1
fi

validate_action_string() {
    local action="$1"
    if [[ "$action" == *$'\n'* || "$action" == *$'\r'* ]]; then
        echo "⚠️  检测到换行符，拒绝执行: $action"
        return 1
    fi
    if [[ "$action" =~ [\;\&\|\<\>\$\`\\] ]]; then
        echo "⚠️  检测到不安全字符，拒绝执行: $action"
        return 1
    fi
    return 0
}

parse_action_args() {
    local action="$1"
    if command -v python3 &>/dev/null; then
        local args_json
        args_json=$(ACTION="$action" python3 - <<'PY'
import json, os, shlex, sys
action = os.environ.get("ACTION", "")
try:
    args = shlex.split(action)
except ValueError:
    sys.exit(1)
print(json.dumps(args))
PY
        ) || return 1
        mapfile -t ACTION_ARGS < <(echo "$args_json" | jq -r '.[]')
    else
        read -r -a ACTION_ARGS <<< "$action"
    fi
    return 0
}

is_allowed_command() {
    local cmd="$1"
    local allowed_list="${VOICE_ALLOWED_COMMANDS:-}"
    local allowed
    if [[ -n "$allowed_list" ]]; then
        IFS=',' read -r -a allowed <<< "$allowed_list"
    else
        allowed=(ls pwd whoami date uptime id uname df du ps top free cat head tail wc stat rg find grep git jq python3)
    fi
    for item in "${allowed[@]}"; do
        if [[ "$cmd" == "$item" ]]; then
            return 0
        fi
    done
    return 1
}

# Additional safety: block dangerous commands
DANGEROUS_PATTERNS="rm -rf|sudo|chmod 777|mkfs|dd if=|>\s*/dev/|curl.*\|.*sh|wget.*\|.*sh"
if echo "$ACTION" | grep -qE "$DANGEROUS_PATTERNS"; then
    echo "⚠️  检测到危险命令模式，跳过执行: $ACTION"
    exit 1
fi

# Handle local symbolic actions (from local intent analysis)
handle_local_action() {
    local action="$1"
    case "$action" in
        run_test)
            echo "【执行测试命令】"
            echo "Running: pwd && ls -la"
            pwd
            ls -la
            ;;
        show_help)
            echo "【帮助】"
            echo "支持的命令: ls, pwd, date, uptime, whoami, cat, head, tail, wc, stat, df, du, ps, git, jq"
            echo ""
            echo "示例语音命令："
            echo "- '列出文件' -> 执行 ls"
            echo "- '当前时间' -> 执行 date"
            echo "- '系统状态' -> 执行 uptime"
            ;;
        list_commands)
            echo "【可用命令列表】"
            echo "ls, pwd, date, uptime, whoami, cat, head, tail, wc, stat, df, du, ps, git, jq"
            ;;
        show_status)
            echo "【系统状态】"
            uptime
            echo ""
            df -h
            ;;
        get_time)
            echo "【当前时间】"
            date
            ;;
        get_weather)
            echo "【天气信息】"
            echo "请使用天气命令查看天气"
            ;;
        review_request)
            echo "⚠️  检测到潜在危险请求，需要人工审核"
            ;;
        none|null)
            echo "未识别到有效命令"
            ;;
        *)
            return 1  # Not a local action, let shell handle it
            ;;
    esac
    return 0
}

# Try local action handler first
if handle_local_action "$ACTION"; then
    exit 0
fi

if ! validate_action_string "$ACTION"; then
    exit 1
fi

if ! parse_action_args "$ACTION"; then
    echo "⚠️  无法解析命令，拒绝执行: $ACTION"
    exit 1
fi

if [[ ${#ACTION_ARGS[@]} -eq 0 ]]; then
    echo "⚠️  命令为空，拒绝执行"
    exit 1
fi

if [[ "${ACTION_ARGS[0]}" == */* ]]; then
    echo "⚠️  禁止执行带路径的命令: ${ACTION_ARGS[0]}"
    exit 1
fi

if ! is_allowed_command "${ACTION_ARGS[0]}"; then
    echo "⚠️  未在允许列表中，拒绝执行: ${ACTION_ARGS[0]}"
    exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo "【Dry Run】命令: $ACTION"
else
    echo "【执行中...】"
    echo "执行命令: $ACTION"
    "${ACTION_ARGS[@]}" 2>&1 || echo "命令执行失败或需要人工处理"
fi
