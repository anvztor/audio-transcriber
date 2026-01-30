#!/bin/bash
# Optimized prompts for Gemini API transcription and intent analysis

set -e
set -u

# Load known vocabulary for prompt enhancement
HOME_DIR="${HOME:-/tmp}"
CLAWDBOT_HOME="${CLAWDBOT_HOME:-$HOME_DIR/.clawdbot}"
VOCAB_FILE="${VOCAB_FILE:-$CLAWDBOT_HOME/config/vocabulary.json}"

# Get known terms from vocabulary file
get_known_terms() {
    if [[ -f "$VOCAB_FILE" ]]; then
        jq -r '.known_terms[]? // empty' "$VOCAB_FILE" 2>/dev/null | tr '\n' ',' | sed 's/,$//'
    else
        echo "clawdbot,anvz,processed,inbound,outbound"
    fi
}

# Build optimized transcription prompt
# Includes language hints and known vocabulary for better accuracy
build_transcription_prompt() {
    local known_terms
    known_terms=$(get_known_terms)

    cat << EOF
请将这段音频转录成文字。

注意事项：
1. 音频可能包含中文或英文，或两者混合
2. 以下是可能出现的专有名词，请优先识别：${known_terms}
3. 只输出转录的文字内容，不要添加任何解释或标点以外的内容
4. 如果听不清某些词，请根据上下文合理推断

只输出转录结果。
EOF
}

# Build intent analysis prompt
build_intent_prompt() {
    local context="${1:-}"
    local known_terms
    known_terms=$(get_known_terms)

    local prompt="请分析用户语音指令，提取需求。

可能出现的专有名词：${known_terms}
"

    if [[ -n "$context" ]]; then
        prompt="${prompt}
当前上下文：${context}
"
    fi

    prompt="${prompt}
输出格式（JSON）：
{
    \"text\": \"转录的原始文字\",
    \"intent\": \"用户的核心需求（一句话）\",
    \"task_type\": \"read|exec|memory|search|help|other\",
    \"confidence\": 0.0-1.0
}

只输出JSON，不要其他内容。"

    echo "$prompt"
}

# Build execution prompt for voice commands
build_execution_prompt() {
    local context="${1:-}"
    local known_terms
    known_terms=$(get_known_terms)

    cat << EOF
分析用户语音指令，确定需要执行的操作。

可能出现的专有名词：${known_terms}
${context:+当前上下文：$context}

输出格式（JSON）：
{
    "text": "转录的文字",
    "intent": "用户想要什么",
    "action": "建议执行的命令或操作",
    "safe": true/false (操作是否安全)
}

只输出JSON。
EOF
}

# Build simple transcription prompt (faster, less context)
build_simple_prompt() {
    echo "请将这段音频转录成文字，只输出文字内容。"
}

# Select best model based on operation type
select_model() {
    local operation="${1:-transcribe}"

    case "$operation" in
        # Simple transcription - can use lighter model
        simple|transcribe)
            echo "gemini-2.5-flash"
            ;;
        # Intent analysis needs better understanding
        intent|execute)
            echo "gemini-2.5-flash"
            ;;
        *)
            echo "gemini-2.5-flash"
            ;;
    esac
}
