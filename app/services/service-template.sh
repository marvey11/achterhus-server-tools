#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly SERVICE_NAME="my-data-collector"
readonly TELEMETRY_URL="${TELEMETRY_URL:-https://api.example.com/v1/telemetry}"

# -----------------------------------------------------------------------------
# Telemetry Functions
# -----------------------------------------------------------------------------

# 1. Initial creation (POST)
send_telemetry_start() {
    if [ "$#" -lt 3 ]; then
        printf 'Error: Missing required arguments for send_telemetry_start.\n' >&2
        return 1
    fi

    local endpoint_url="$1"
    local service_name="$2"
    local run_id="$3"
    local started_at="${4:-}"

    if [ -z "$started_at" ]; then
        started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    fi

    local payload
    if ! payload=$(jq -n \
        --arg service_name "$service_name" \
        --arg run_id "$run_id" \
        --arg status "RUNNING" \
        --arg started_at "$started_at" \
        '{
            service_name: $service_name,
            run_id: $run_id,
            status: $status,
            started_at: $started_at
        }'
    ); then
        printf 'Error: Failed to construct initial JSON payload.\n' >&2
        return 1
    fi

    curl --fail --silent --show-error \
        --request POST \
        --header "Content-Type: application/json" \
        --data "$payload" \
        "$endpoint_url"
}

# 2. Status update (PATCH)
send_telemetry_finish() {
    if [ "$#" -lt 2 ]; then
        printf 'Error: Missing required arguments for send_telemetry_finish.\n' >&2
        return 1
    fi

    local endpoint_url="$1"
    local run_id="$2"
    local status="${3:-SUCCESS}"
    local ended_at="${4:-}"
    local duration_seconds="${5:-}"
    local metrics_json="${6:-{}}"
    local error_message="${7:-}"
    local logs_summary="${8:-}"

    if [ -z "$ended_at" ]; then
        ended_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    fi

    if ! echo "$metrics_json" | jq -e 'if type == "object" then true else false end' >/dev/null 2>&1; then
        printf 'Error: metrics_json must be a valid JSON object string.\n' >&2
        return 1
    fi

    local payload
    if ! payload=$(jq -n \
        --arg status "$status" \
        --arg ended_at "$ended_at" \
        --arg duration_seconds "$duration_seconds" \
        --argjson metrics "$metrics_json" \
        --arg error_message "$error_message" \
        --arg logs_summary "$logs_summary" \
        '{
            status: $status,
            ended_at: (if $ended_at == "" then null else $ended_at end),
            duration_seconds: (if $duration_seconds == "" then null else ($duration_seconds | tonumber) end),
            metrics: $metrics,
            error_message: (if $error_message == "" then null else $error_message end),
            logs_summary: (if $logs_summary == "" then null else $logs_summary end)
        }'
    ); then
        printf 'Error: Failed to construct patch JSON payload.\n' >&2
        return 1
    fi

    # Append run_id to the base URL for entity targeting
    local patch_url="${endpoint_url%/}/${run_id}"

    curl --fail --silent --show-error \
        --request PATCH \
        --header "Content-Type: application/json" \
        --data "$payload" \
        "$patch_url"
}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        jq -rn '
            [range(16)] | map(if . == 6 then (random * 16 | floor | . % 16 | . + 64)
                              elif . == 8 then (random * 16 | floor | . % 4 | . + 128)
                              else (random * 256 | floor) end)
            | map(if . < 16 then "0" else "" end + tostring) | join("")
            | "\(.[0:8])-\(.[8:12])-\(.[12:16])-\(.[16:20])-\(.[20:32])"
        '
    fi
}

get_iso8601() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# -----------------------------------------------------------------------------
# Global State & Trap Setup
# -----------------------------------------------------------------------------
RUN_ID="$(generate_uuid)"
STARTED_AT="$(get_iso8601)"
START_TIME="$(date +%s)"

ERR_LOG="$(mktemp)"
METRICS_JSON="{}"

cleanup_and_report() {
    local exit_code=$?
    trap - EXIT

    local ended_at
    ended_at="$(get_iso8601)"

    local end_time
    end_time="$(date +%s)"

    local duration_seconds
    duration_seconds=$(( end_time - START_TIME ))

    local status="SUCCESS"
    local error_msg=""
    local logs_summary=""

    if [ "$exit_code" -ne 0 ]; then
        status="FAILED"
        if [ -s "$ERR_LOG" ]; then
            logs_summary="$(tail -n 10 "$ERR_LOG" | tr '\n' ' ' | sed 's/"/\\"/g')"
            error_msg="Script terminated with exit code $exit_code. stderr summary: $logs_summary"
        else
            error_msg="Script terminated with exit code $exit_code."
        fi
    fi

    printf '\n[Telemetry] Patching run status: %s (Duration: %ss)\n' "$status" "$duration_seconds"
    send_telemetry_finish \
        "$TELEMETRY_URL" \
        "$RUN_ID" \
        "$status" \
        "$ended_at" \
        "$duration_seconds" \
        "$METRICS_JSON" \
        "$error_msg" \
        "$logs_summary" || printf 'Warning: Failed to send telemetry patch update.\n' >&2

    rm -f "$ERR_LOG"
}

trap cleanup_and_report EXIT
exec 2> >(tee -a "$ERR_LOG" >&2)

# -----------------------------------------------------------------------------
# Main Business Logic
# -----------------------------------------------------------------------------
run_service() {
    printf 'Starting service execution (RUN_ID: %s)...\n' "$RUN_ID"

    # Send initial POST to create the record
    send_telemetry_start \
        "$TELEMETRY_URL" \
        "$SERVICE_NAME" \
        "$RUN_ID" \
        "$STARTED_AT" || true

    # Simulate workload
    sleep 2

    local items_processed=1250
    local records_failed=3
    local memory_peak_mb=128

    METRICS_JSON=$(jq -n \
        --argjson items "$items_processed" \
        --argjson failed "$records_failed" \
        --argjson memory "$memory_peak_mb" \
        '{
            items_processed: $items,
            records_failed: $failed,
            memory_peak_mb: $memory
        }'
    )

    printf 'Successfully processed %s records.\n' "$items_processed"
}

main() {
    run_service
}

main "$@"
