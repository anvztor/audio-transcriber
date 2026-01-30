#!/usr/bin/env bats
# Unit tests for corrections.py module

setup() {
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")/../scripts" && pwd)"
    export CORRECTIONS_PY="$SCRIPT_DIR/lib/corrections.py"
}

apply_corrections() {
    echo "$1" | python3 "$CORRECTIONS_PY"
}

@test "corrections: fixes cloudboot -> clawdbot" {
    result=$(apply_corrections "cloudboot is great")
    [ "$result" = "clawdbot is great" ]
}

@test "corrections: fixes cloud boot -> clawdbot" {
    result=$(apply_corrections "cloud boot is great")
    [ "$result" = "clawdbot is great" ]
}

@test "corrections: fixes CLOUDBOOT (case insensitive)" {
    result=$(apply_corrections "CLOUDBOOT test")
    [ "$result" = "clawdbot test" ]
}

@test "corrections: fixes pro system -> processed" {
    result=$(apply_corrections "the file is pro system")
    [ "$result" = "the file is processed" ]
}

@test "corrections: fixes AMVZ -> anvz" {
    result=$(apply_corrections "check AMVZ folder")
    [ "$result" = "check anvz folder" ]
}

@test "corrections: fixes amvz -> anvz" {
    result=$(apply_corrections "in amvz directory")
    [ "$result" = "in anvz directory" ]
}

@test "corrections: fixes AVZ -> anvz" {
    result=$(apply_corrections "look in AVZ")
    [ "$result" = "look in anvz" ]
}

@test "corrections: handles Chinese correction 帮你 -> 帮我" {
    result=$(apply_corrections "帮你看一下")
    [ "$result" = "帮我看一下" ]
}

@test "corrections: preserves correct text unchanged" {
    result=$(apply_corrections "clawdbot is working")
    [ "$result" = "clawdbot is working" ]
}

@test "corrections: handles multiple corrections in one text" {
    result=$(apply_corrections "cloudboot pro system AMVZ")
    [ "$result" = "clawdbot processed anvz" ]
}

@test "corrections: handles empty input" {
    result=$(apply_corrections "")
    [ "$result" = "" ]
}

@test "corrections: preserves whitespace and punctuation" {
    result=$(apply_corrections "cloudboot, is great!")
    [ "$result" = "clawdbot, is great!" ]
}

@test "corrections: fuzzy match clowdbot -> clawdbot" {
    result=$(apply_corrections "clowdbot test")
    [ "$result" = "clawdbot test" ]
}

@test "corrections: fuzzy match prosess -> processed" {
    result=$(apply_corrections "file is prosess")
    [ "$result" = "file is processed" ]
}
