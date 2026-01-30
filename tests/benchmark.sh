#!/bin/bash
# Performance benchmark for audio transcriber optimization
# Measures conversion time, encoding time, and total latency

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_FILE="/tmp/benchmark_results.txt"

# Source libraries for individual benchmarks
source "$SCRIPT_DIR/lib/convert-audio.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_result() {
    echo "$1" | tee -a "$RESULTS_FILE"
}

# Measure execution time in milliseconds
measure_time() {
    local start_ns=$(date +%s%N)
    eval "$@" >/dev/null 2>&1
    local end_ns=$(date +%s%N)
    echo $(( (end_ns - start_ns) / 1000000 ))
}

# Create test audio file
create_test_audio() {
    local duration="${1:-2}"
    local output="${2:-/tmp/test_audio.ogg}"

    ffmpeg -f lavfi -i "sine=frequency=440:duration=$duration" \
        -c:a libvorbis -q:a 4 "$output" -y 2>/dev/null

    echo "$output"
}

# Benchmark: Audio conversion
benchmark_conversion() {
    local audio_file="$1"
    local iterations="${2:-5}"

    log_result ""
    log_result "=== Audio Conversion Benchmark ==="

    # Clear cache for fair comparison
    rm -rf /tmp/audio-cache 2>/dev/null || true

    # First run (no cache)
    local first_run=$(measure_time convert_audio "$audio_file")
    log_result "First run (no cache): ${first_run}ms"

    # Subsequent runs (with cache)
    local total=0
    for i in $(seq 1 $iterations); do
        local time_ms=$(measure_time convert_audio "$audio_file")
        total=$((total + time_ms))
    done
    local avg=$((total / iterations))
    log_result "Cached runs (avg of $iterations): ${avg}ms"

    # Report speedup
    if [[ $avg -gt 0 && $first_run -gt 0 ]]; then
        local speedup=$((first_run * 100 / avg))
        log_result "Cache speedup: ${speedup}%"
    else
        log_result "Cache speedup: instant (< 1ms per operation)"
    fi
}

# Benchmark: Base64 encoding
benchmark_encoding() {
    local audio_file="$1"
    local iterations="${2:-10}"

    log_result ""
    log_result "=== Base64 Encoding Benchmark ==="

    local total=0
    for i in $(seq 1 $iterations); do
        local time_ms=$(measure_time encode_audio_base64 "$audio_file")
        total=$((total + time_ms))
    done
    local avg=$((total / iterations))
    log_result "Encoding time (avg of $iterations): ${avg}ms"

    # File size
    local size
    size=$(stat -c %s "$audio_file" 2>/dev/null) || size=$(stat -f %z "$audio_file" 2>/dev/null) || size=0
    local size_kb=$((size / 1024))
    log_result "File size: ${size_kb}KB"
    if [[ $avg -gt 0 ]]; then
        log_result "Throughput: $((size_kb * 1000 / avg))KB/s"
    else
        log_result "Throughput: instant (< 1ms)"
    fi
}

# Benchmark: Correction patterns
benchmark_corrections() {
    local iterations="${2:-100}"

    log_result ""
    log_result "=== Correction Pattern Benchmark ==="

    local test_text="cloudboot pro system AMVZ 帮你看一下"

    local start_ns=$(date +%s%N)
    for i in $(seq 1 $iterations); do
        echo "$test_text" | python3 "$SCRIPT_DIR/lib/corrections.py" >/dev/null
    done
    local end_ns=$(date +%s%N)

    local total_ms=$(( (end_ns - start_ns) / 1000000 ))
    local avg_ms=$((total_ms / iterations))
    log_result "Correction time (avg of $iterations): ${avg_ms}ms"

    # Verify corrections work
    local result=$(echo "$test_text" | python3 "$SCRIPT_DIR/lib/corrections.py")
    if [[ "$result" == "clawdbot processed anvz 帮我看一下" ]]; then
        log_result "Correction accuracy: PASS"
    else
        log_result "Correction accuracy: FAIL (got: $result)"
    fi
}

# Full pipeline benchmark (requires API key)
benchmark_full_pipeline() {
    local audio_file="$1"

    log_result ""
    log_result "=== Full Pipeline Benchmark ==="

    if [[ -z "$GEMINI_API_KEY" ]]; then
        log_result "Skipped: GEMINI_API_KEY not set"
        return 0
    fi

    # Measure full transcription
    local start_ns=$(date +%s%N)
    "$SCRIPT_DIR/transcribe-and-correct.sh" "$audio_file" >/dev/null 2>&1
    local end_ns=$(date +%s%N)

    local total_ms=$(( (end_ns - start_ns) / 1000000 ))
    log_result "Full pipeline time: ${total_ms}ms"

    # Second run (cached conversion)
    start_ns=$(date +%s%N)
    "$SCRIPT_DIR/transcribe-and-correct.sh" "$audio_file" >/dev/null 2>&1
    end_ns=$(date +%s%N)

    local cached_ms=$(( (end_ns - start_ns) / 1000000 ))
    log_result "Full pipeline (cached): ${cached_ms}ms"

    if [[ $cached_ms -lt $total_ms ]]; then
        local savings=$((total_ms - cached_ms))
        log_result "Time saved with cache: ${savings}ms"
    fi
}

# Main
main() {
    echo "Audio Transcriber Performance Benchmark"
    echo "========================================"
    echo ""

    # Clear previous results
    > "$RESULTS_FILE"

    log_result "Benchmark started: $(date)"
    log_result "Script directory: $SCRIPT_DIR"

    # Create test audio files
    log_result ""
    log_result "Creating test audio files..."

    local short_audio=$(create_test_audio 1 /tmp/test_short.ogg)
    local medium_audio=$(create_test_audio 5 /tmp/test_medium.ogg)

    log_result "Short audio: $short_audio"
    log_result "Medium audio: $medium_audio"

    # Run benchmarks
    benchmark_conversion "$short_audio"
    benchmark_encoding "$short_audio"
    benchmark_corrections

    # Full pipeline (optional, requires API key)
    benchmark_full_pipeline "$short_audio"

    # Cleanup
    rm -f /tmp/test_short.ogg /tmp/test_medium.ogg

    log_result ""
    log_result "Benchmark completed: $(date)"
    log_result "Results saved to: $RESULTS_FILE"

    echo ""
    echo -e "${GREEN}Benchmark complete!${NC}"
    echo "Full results: $RESULTS_FILE"
}

main "$@"
