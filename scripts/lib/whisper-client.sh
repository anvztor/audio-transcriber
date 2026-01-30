#!/bin/bash
# Local Whisper transcription library

set -e
set -u

WHISPER_DEFAULT_MODEL="${WHISPER_MODEL:-base}"

check_whisper_installed() {
    if ! command -v python3 &>/dev/null; then
        return 1
    fi
    if ! command -v ffmpeg &>/dev/null; then
        return 1
    fi
    python3 - <<'PY' >/dev/null 2>&1
import whisper
PY
}

install_whisper_if_needed() {
    if check_whisper_installed; then
        return 0
    fi

    if ! command -v python3 &>/dev/null; then
        echo "error: python3 not found" >&2
        return 1
    fi

    if ! command -v ffmpeg &>/dev/null; then
        echo "error: ffmpeg not found" >&2
        return 1
    fi

    if ! python3 -m pip --version &>/dev/null; then
        python3 -m ensurepip --user >/dev/null 2>&1 || true
    fi

    python3 -m pip install --user -U openai-whisper
    check_whisper_installed
}

transcribe_audio_whisper() {
    local audio_file="$1"
    local model="${2:-$WHISPER_DEFAULT_MODEL}"
    local preprocessed_audio=""

    if [[ -z "$audio_file" || ! -f "$audio_file" ]]; then
        echo "error: audio file not found" >&2
        return 1
    fi

    preprocessed_audio="$(mktemp -t whisper-preprocessed-XXXXXX.wav)"
    trap 'rm -f "$preprocessed_audio"' RETURN

    ffmpeg -hide_banner -loglevel error -y -nostdin \
        -i "$audio_file" \
        -vn -ac 1 -ar 16000 \
        -filter:a "highpass=300, lowpass=3000, loudnorm" \
        "$preprocessed_audio"

    python3 - "$preprocessed_audio" "$model" <<'PY'
import sys
import whisper

audio_path = sys.argv[1]
model_name = sys.argv[2]

model = whisper.load_model(model_name)
result = model.transcribe(audio_path, fp16=False, verbose=False)
text = (result.get("text") or "").strip()

sys.stdout.write(text)
PY
}
