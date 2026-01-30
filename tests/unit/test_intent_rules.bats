#!/usr/bin/env bats
# Unit tests for intent-rules.sh library

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")/../scripts" && pwd)"
    source "$SCRIPT_DIR/lib/intent-rules.sh"
}

@test "analyze_intent_local: matches basic intents" {
    local result
    result=$(analyze_intent_local "please run a test")
    [ "$(echo "$result" | jq -r '.intent')" = "test" ]
    [ "$(echo "$result" | jq -r '.action')" = "run_test" ]

    result=$(analyze_intent_local "help me with commands")
    [ "$(echo "$result" | jq -r '.intent')" = "help" ]

    result=$(analyze_intent_local "list available commands")
    [ "$(echo "$result" | jq -r '.intent')" = "list" ]

    result=$(analyze_intent_local "what is the status")
    [ "$(echo "$result" | jq -r '.intent')" = "status" ]
}

@test "analyze_intent_local: flags unsafe requests" {
    local result
    result=$(analyze_intent_local "delete all files")
    [ "$(echo "$result" | jq -r '.safe')" = "false" ]
    [ "$(echo "$result" | jq -r '.intent')" = "unsafe" ]
}

@test "analyze_intent_local: handles unknown intent" {
    local result
    result=$(analyze_intent_local "sing me a song")
    [ "$(echo "$result" | jq -r '.intent')" = "unknown" ]
    [ "$(echo "$result" | jq -r '.action')" = "none" ]
    [ "$(echo "$result" | jq -r '.safe')" = "true" ]
}
